/*
 * Copyright © 2021-2022 Michał 'Griwes' Dominiak
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

#include "../arch/vm.h"
#include "addresses.h"
#include "print.h"
#include "process.h"

#include <archive/cpio.h>

#include <user/meta.h>

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

namespace sc = rose::syscall;

extern "C" [[gnu::section(".bootinit_entry")]] int bootinit_main(std::uintptr_t mailbox_token)
{
    __init();

    sc::mailbox_message message;

    auto result = sc::rose_mailbox_read(mailbox_token, 0, &message);
    if (result != sc::result::ok || message.type != sc::mailbox_message_type::handle_token)
    {
        // ... panic ...
        *reinterpret_cast<volatile std::uintptr_t *>(0) = 0;
    }

    bootinit::facts::acceptor_mailbox_token = message.payload.handle_token;
    kernel_print::initialize(bootinit::facts::acceptor_mailbox_token);

    kernel_print::println("Receiving initial handle tokens...");

    result = sc::rose_mailbox_read(mailbox_token, -1, &message);
    if (result != sc::result::ok)
    {
        PANIC("Failed to read kernel caps token!");
    }

    if (message.type != sc::mailbox_message_type::handle_token)
    {
        PANIC("Received wrong mailbox message type for kernel caps token!");
    }

    bootinit::facts::kernel_caps_token = message.payload.handle_token;
    kernel_print::println(" > Kernel caps token received.");

    result = sc::rose_mailbox_read(mailbox_token, -1, &message);
    if (result != sc::result::ok)
    {
        PANIC("Failed to read initrd VMO token!");
    }

    if (message.type != sc::mailbox_message_type::handle_token)
    {
        PANIC("Received wrong mailbox message type for initrd VMO token!");
    }

    [[maybe_unused]] auto initrd_vmo = message.payload.handle_token;
    kernel_print::println(" > Initrd VMO token received.");

    result = sc::rose_mailbox_read(mailbox_token, -1, &message);
    if (result != sc::result::ok)
    {
        PANIC("Failed to read file sizes!");
    }

    if (message.type != sc::mailbox_message_type::user)
    {
        PANIC("Received wrong mailbox message type for file sizes!");
    }

    auto initrd_size = message.payload.user.data0;
    bootinit::facts::vdso_size = message.payload.user.data1;

    kernel_print::println(" > Initrd size: {} bytes.", initrd_size);

    result = sc::rose_mailbox_read(mailbox_token, -1, &message);
    if (result != sc::result::ok)
    {
        PANIC("Failed to read bootinit VAS token!");
    }

    if (message.type != sc::mailbox_message_type::handle_token)
    {
        PANIC("Received wrong mailbox message type for bootinit VAS token!");
    }

    bootinit::facts::self_vas_token = message.payload.handle_token;

    kernel_print::println("Parsing initrd image...");

    auto initrd_result =
        archive::try_cpio(reinterpret_cast<char *>(bootinit::addresses::initrd.value()), initrd_size);

    if (!initrd_result.archive)
    {
        PANIC(
            "The initrd image is not a valid cpio archive! Reason: {}, header offset: {}.",
            initrd_result.error_message,
            initrd_result.header_offset);
    }

    auto & initrd = *initrd_result.archive;

    kernel_print::println(" > Number of regular files in initrd: {}.", initrd.size());

    kernel_print::println("Creating logger process...");
    [[maybe_unused]] auto [logger_process, logger_vas, logger_protocol_mailbox] =
        bootinit::process::create_process(initrd, "system/logger.srv", "logger");

    // TODO: this needs to clone the token?
    message.type = sc::mailbox_message_type::handle_token;
    message.payload.handle_token = logger_process;
    result = sc::rose_mailbox_write(bootinit::facts::acceptor_mailbox_token, &message);
    if (result != sc::result::ok)
    {
        PANIC("failed to send the logger process token to the log acceptor!");
    }

    // TODO: make this remove the transfer permission
    message.type = sc::mailbox_message_type::handle_token;
    message.payload.handle_token = bootinit::facts::acceptor_mailbox_token;
    result = sc::rose_mailbox_write(logger_protocol_mailbox, &message);
    if (result != sc::result::ok)
    {
        PANIC("failed to send the log acceptor token! {}", std::to_underlying(result));
    }

    /*
    kernel_print::println("Creating vasmgr process...");

    [[maybe_unused]] auto [vasmgr_process, vasmgr_vas, vasmgr_protocol_mailbox] =
        create_process(initrd, "system/vasmgr.srv", "vasmgr");
    */

    /*
    auto procmgr_image = initrd["system/procmgr.srv"];
    if (!procmgr_image)
    {
        PANIC("system/procmgr.srv not found in the initrd image!");
    }

    auto [procmgr_process, procmgr_vas, procmgr_protocol_mailbox] = create_process(*procmgr_image);

    auto broker_image = initrd["system/broker.srv"];
    if (!broker_image)
    {
        PANIC("system/broker.srv not found in the initrd image!");
    }

    auto [broker_process, broker_vas, broker_protocol_mailbox] = create_process(*broker_image);
    */

    for (;;)
        ;
}
