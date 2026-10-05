/*
 * Copyright © 2021-2025 Michał 'Griwes' Dominiak
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "arch/common/acpi/acpi.h"
#include "arch/cpu.h"
#include "arch/mp.h"
#include "boot/screen.h"
#include "bootinit/addresses.h"
#include "memory/pmm.h"
#include "memory/vmo.h"
#include "scheduler/mailbox.h"
#include "scheduler/scheduler.h"
#include "scheduler/thread.h"
#include "time/time.h"
#include "util/log.h"
#include "util/mp.h"

#include <boot-arguments.h>
#include <boot-constants.h>
#include <boot-memmap.h>
#include <boot-video.h>

#include <cstddef>
#include <cstdint>

using ctor_t = void (*)();
// Linker boundaries may coincide when the constructor array is empty.
extern "C" ctor_t __start_ctors[];
extern "C" ctor_t __end_ctors[];

extern "C" void __init()
{
    for (auto ctor = __start_ctors; ctor != __end_ctors; ++ctor)
    {
        (*ctor)();
    }
}

extern "C" void __cxa_atexit(void (*)(void *), void *, void *)
{
}

extern "C" [[noreturn]] void __cxa_pure_virtual()
{
    PANIC("Pure virtual method called!");
}

void operator delete(void *, unsigned long) noexcept
{
    PANIC("operator delete called!");
}

extern "C" char begin_bootinit[];
extern "C" char end_bootinit[];

extern "C" char begin_vdso[];
extern "C" char end_vdso[];

namespace
{
kernel::phys_addr_t initrd_base;
std::size_t initrd_size;

const char * process_tags[] = { "bootinit", "logger", "temporaryhack" };

void log_handler(
    std::uintptr_t log_mailbox,
    std::uintptr_t ack_mailbox,
    const char * process_tag,
    kernel::scheduler::process * process,
    kernel::vm::vmo_mapping * mapping)
{
    kernel::util::intrusive_ptr stack_mapping(mapping, kernel::util::adopt);

    while (true)
    {
        rose::syscall::mailbox_message msg{};

        auto result = rose::syscall::rose_mailbox_read(log_mailbox, 0, &msg);

        if (result != rose::syscall::result::ok)
        {
            PANIC(
                "failed to receive a message from the {} logging mailbox: {}",
                process_tag,
                std::to_underlying(result));
        }

        if (msg.type != rose::syscall::mailbox_message_type::user)
        {
            PANIC("{} logging mailbox contained a message of a wrong type!", process_tag);
        }

        if (msg.payload.user.data0 == 0)
        {
            break;
        }

        auto start = kernel::virt_addr_t(msg.payload.user.data0);
        auto end = start + msg.payload.user.data1;

        {
            kernel::util::interrupt_guard guard;

            auto lock = process->get_vas()->lock_address_range(start, end, false);

            if (!lock)
            {
                PANIC("{} logging mailbox contained a message pointing to an unmapped address!", process_tag);
            }

            {
                std::lock_guard _(kernel::log::log_lock);
                auto it = kernel::boot_log::iterator();
                *it++ = '[';
                for (auto ptr = process_tag; *ptr != 0; ++ptr)
                {
                    *it++ = *ptr;
                }
                *it++ = ']';
                *it++ = ' ';
                for (auto ptr = reinterpret_cast<char *>(start.value());
                     ptr != reinterpret_cast<char *>(end.value());
                     ++ptr)
                {
                    *it++ = *ptr;
                }
            }
        }

        msg.payload = {};

        result = rose::syscall::rose_mailbox_write(ack_mailbox, &msg);
        if (result != rose::syscall::result::ok)
        {
            PANIC("failed to send an ack message to the {} logging mailbox!", process_tag);
        }
    }

    PANIC("TODO: implement thread termination");
}

void log_acceptor(std::uintptr_t accept_mailbox, kernel::vm::vmo_mapping * mapping)
{
    auto process_tag = process_tags;

    kernel::util::intrusive_ptr stack_mapping(mapping, kernel::util::adopt);

    rose::syscall::mailbox_message msg{};

    auto read_valid_token = [&]
    {
        auto result = rose::syscall::rose_mailbox_read(accept_mailbox, 0, &msg);

        if (result != rose::syscall::result::ok)
        {
            PANIC("failed to read a message from the log acceptor mailbox: {}", std::to_underlying(result));
        }

        if (msg.type != rose::syscall::mailbox_message_type::handle_token)
        {
            PANIC("wrong message type in the log acceptor mailbox");
        }

        auto handle = kernel::scheduler::get_kernel_process()->get_handle(
            kernel::handle_token_t(msg.payload.handle_token));
        if (!handle)
        {
            PANIC("invalid handle token received from the log acceptor mailbox");
        }

        return handle;
    };

    while (process_tag != std::end(process_tags))
    {
        auto process_handle = read_valid_token();
        if (!process_handle->is_a<kernel::scheduler::process>())
        {
            PANIC("wrong handle type received from the log acceptor mailbox");
        }

        auto process = process_handle->get_as<kernel::scheduler::process>();

        kernel::log::println("[kernel/log-acceptor] Received process handle.");

        auto log_mailbox_handle = read_valid_token();
        if (!log_mailbox_handle->is_a<kernel::ipc::mailbox>())
        {
            PANIC("wrong handle type received from the log acceptor mailbox");
        };

        auto log_mailbox = log_mailbox_handle->get_as<kernel::ipc::mailbox>();

        kernel::log::println("[kernel/log-acceptor] Received log mailbox handle.");

        auto ack_mailbox_handle = read_valid_token();
        if (!ack_mailbox_handle->is_a<kernel::ipc::mailbox>())
        {
            PANIC("wrong handle type received from the log acceptor mailbox");
        };

        auto ack_mailbox = ack_mailbox_handle->get_as<kernel::ipc::mailbox>();

        kernel::log::println("[kernel/log-acceptor] Received ack mailbox handle.");
        kernel::log::println("[kernel/log-acceptor] Creating log handler thread for {}.", *process_tag);

        // TODO: abstraction for this, create_kernel_thread or something
        auto log_stack_addr = kernel::vm::allocate_address_range(32 * kernel::arch::vm::page_sizes[0]);
        auto log_stack_vmo = kernel::vm::create_sparse_vmo(31 * kernel::arch::vm::page_sizes[0]);
        log_stack_vmo->commit_all();
        auto log_stack_mapping = process->get_vas()->map_vmo(
            std::move(log_stack_vmo), log_stack_addr + kernel::arch::vm::page_sizes[0]);

        auto log_thread = process->create_thread();
        log_thread->get_context()->set_instruction_pointer(
            kernel::virt_addr_t(reinterpret_cast<std::uintptr_t>(&log_handler)));
        log_thread->get_context()->set_stack_pointer(
            log_stack_addr + 32 * kernel::arch::vm::page_sizes[0] - 8);
        log_thread->get_context()->set_argument(
            0,
            process->register_for_token(
                kernel::create_handle(std::move(log_mailbox), rose::syscall::permissions::read)));
        log_thread->get_context()->set_argument(
            1,
            process->register_for_token(
                kernel::create_handle(std::move(ack_mailbox), rose::syscall::permissions::write)));
        log_thread->get_context()->set_argument(2, reinterpret_cast<std::uintptr_t>(*process_tag));
        log_thread->get_context()->set_argument(3, reinterpret_cast<std::uintptr_t>(process));
        log_thread->get_context()->set_argument(
            4, reinterpret_cast<std::uintptr_t>(log_stack_mapping.release(kernel::util::keep_count)));

        kernel::util::interrupt_guard guard;
        kernel::scheduler::schedule(std::move(log_thread));

        ++process_tag;
    }

    rose::syscall::rose_token_release(accept_mailbox);

    PANIC("implement thread termination");
}

}

extern "C" [[gnu::section(".reaveros_entry")]] void kernel_main(boot_protocol::kernel_arguments args)
{
    __init();

    kernel::boot_log::initialize(args.memory_map_size, args.memory_map_entries);
    if (args.has_video_mode)
    {
        kernel::boot_screen::initialize(args.video_mode, args.memory_map_size, args.memory_map_entries);
    }

    kernel::log::println("ReaverOS: Reaver Project Operating System, \"Rose\"");
    kernel::log::println(
        "Version: 0.0.5 dev; Release #1 \"Cotyledon\", built on {} at {}", __DATE__, __TIME__);
    kernel::log::println("Copyright (C) 2021-2025 Reaver Project Team");
    kernel::log::println("");

    kernel::pmm::initialize(args.memory_map_size, args.memory_map_entries);
    kernel::pmm::report();

    kernel::acpi::initialize(args.acpi_revision, kernel::phys_addr_t{ args.acpi_root });
    kernel::arch::cpu::initialize();
    kernel::time::initialize();

    kernel::arch::mp::boot();
    kernel::mp::initialize_parallel();
    kernel::time::initialize_multicore();
    kernel::scheduler::initialize();

    auto initrd_entry = boot_protocol::find_entry(
        args.memory_map_size, args.memory_map_entries, boot_protocol::memory_type::initrd);
    if (!initrd_entry)
    {
        PANIC("Initrd not found!");
    }

    initrd_base = kernel::phys_addr_t(initrd_entry->physical_start);
    initrd_size = initrd_entry->length;

    kernel::arch::cpu::switch_to_clean_state();

    // IIFE to force the compiler to create a stack frame after a stack switch above
    // (otherwise it'd codegen assuming the stack frame of kernel_main is still valid,
    // even when this is not accessing any local variables)
    []() __attribute__((noinline))
    {
        kernel::log::println("[BOOT] Creating VDSO VMO...");

        auto vdso_vmo = kernel::vm::create_physical_vmo(
            kernel::arch::vm::virt_to_phys(kernel::virt_addr_t(reinterpret_cast<std::uintptr_t>(begin_vdso))),
            end_vdso - begin_vdso);
        kernel::vm::set_vdso_vmo(vdso_vmo);

        kernel::log::println("[BOOT] Creating the bootinit process...");

        auto bootinit_vas = kernel::vm::create_vas(false);

        auto bootinit_process = kernel::scheduler::create_process(bootinit_vas);
        auto bootinit_thread = bootinit_process->create_thread();

        kernel::log::println(" > Creating and mapping the bootinit code VMO...");
        auto bootinit_code_vmo = kernel::vm::create_physical_vmo(
            kernel::arch::vm::virt_to_phys(
                kernel::virt_addr_t(reinterpret_cast<std::uintptr_t>(begin_bootinit))),
            end_bootinit - begin_bootinit);
        bootinit_vas->map_vmo(std::move(bootinit_code_vmo), bootinit::addresses::ip, kernel::vm::flags::user);

        kernel::log::println(" > Mapping the VDSO VMO...");
        bootinit_vas->map_vmo(std::move(vdso_vmo), bootinit::addresses::vdso, kernel::vm::flags::user);

        kernel::log::println(" > Creating and mapping the initrd VMO...");
        auto initrd_vmo = kernel::vm::create_physical_vmo(initrd_base, initrd_size);
        bootinit_vas->map_vmo(std::move(initrd_vmo), bootinit::addresses::initrd, kernel::vm::flags::user);

        kernel::log::println(" > Creating and mapping the bootinit stack VMO...");
        auto bootinit_stack_vmo = kernel::vm::create_sparse_vmo(31 * kernel::arch::vm::page_sizes[0]);
        // TODO: remove this once on-demand mappings are a thing
        bootinit_stack_vmo->commit_all();
        bootinit_vas->map_vmo(
            std::move(bootinit_stack_vmo),
            bootinit::addresses::top_of_stack - 31 * kernel::arch::vm::page_sizes[0],
            kernel::vm::flags::user);

        kernel::log::println(" > Creating the bootstrap mailboxes and sending handle tokens...");
        auto bootinit_mailbox = kernel::ipc::create_mailbox();

        kernel::log::println(" >> Creating and sending the log acceptor mailbox...");
        auto log_accept_mailbox = kernel::ipc::create_mailbox();
        auto lab_handle = kernel::create_handle(
            log_accept_mailbox /* not moved on purpose */,
            rose::syscall::permissions::write | rose ::syscall::permissions::transfer);
        bootinit_mailbox->send(std::move(lab_handle));

        log_accept_mailbox->send(kernel::create_handle(bootinit_process));

        kernel::log::println(" >> Sending kernel caps handle token...");
        bootinit_mailbox->send(kernel::create_handle(&kernel::kernel_caps));

        kernel::log::println(" >> Sending initrd VMO handle token and size, and vdso size...");
        bootinit_mailbox->send(kernel::create_handle(std::move(initrd_vmo)));
        bootinit_mailbox->send(rose::syscall::mailbox_user_message{
            .data0 = initrd_size, .data1 = static_cast<std::uintptr_t>(end_vdso - begin_vdso) });

        kernel::log::println(" >> Sending bootinit VAS handle token...");
        bootinit_mailbox->send(
            kernel::create_handle(bootinit_vas, rose::syscall::permissions::create_mapping));

        kernel::log::println(" > Preparing bootinit context...");
        auto bm_handle = kernel::create_handle(std::move(bootinit_mailbox), rose::syscall::permissions::read);
        bootinit_thread->get_context()->set_userspace();
        bootinit_thread->get_context()->set_instruction_pointer(bootinit::addresses::ip);
        bootinit_thread->get_context()->set_stack_pointer(bootinit::addresses::top_of_stack);
        bootinit_thread->get_context()->set_argument(
            0, bootinit_thread->get_container()->register_for_token(std::move(bm_handle)));

        kernel::log::println(" > Preparing log mailbox accepter...");
        // TODO: abstraction for this, create_kernel_thread or something
        auto log_acceptor_stack_addr =
            kernel::vm::allocate_address_range(32 * kernel::arch::vm::page_sizes[0]);
        auto log_acceptor_stack_vmo = kernel::vm::create_sparse_vmo(31 * kernel::arch::vm::page_sizes[0]);
        log_acceptor_stack_vmo->commit_all();
        auto log_acceptor_stack_mapping = kernel::scheduler::get_kernel_process()->get_vas()->map_vmo(
            std::move(log_acceptor_stack_vmo), log_acceptor_stack_addr + kernel::arch::vm::page_sizes[0]);

        auto log_acceptor_thread = kernel::scheduler::get_kernel_process()->create_thread();
        log_acceptor_thread->get_context()->set_instruction_pointer(
            kernel::virt_addr_t(reinterpret_cast<std::uintptr_t>(&log_acceptor)));
        log_acceptor_thread->get_context()->set_stack_pointer(
            log_acceptor_stack_addr + 32 * kernel::arch::vm::page_sizes[0] - 8);
        log_acceptor_thread->get_context()->set_argument(
            0,
            kernel::scheduler::get_kernel_process()->register_for_token(
                kernel::create_handle(std::move(log_accept_mailbox), rose::syscall::permissions::read)));
        log_acceptor_thread->get_context()->set_argument(
            1,
            reinterpret_cast<std::uintptr_t>(log_acceptor_stack_mapping.release(kernel::util::keep_count)));

        kernel::log::println(
            " > Scheduling bootinit thread. Kernel-side init done, servicing early logging requests.");

        {
            kernel::util::interrupt_guard guard;
            kernel::scheduler::schedule(std::move(log_acceptor_thread));
            kernel::scheduler::schedule(std::move(bootinit_thread));
        }

        kernel::arch::cpu::idle();
    }
    ();
}
