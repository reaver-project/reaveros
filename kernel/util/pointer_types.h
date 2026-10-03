/*
 * Copyright © 2021 Michał 'Griwes' Dominiak
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

#pragma once

#include <cstddef>

#include "integer_types.h"

namespace kernel
{
template<typename T, typename Storage = std::uintptr_t>
class [[gnu::packed]] phys_ptr_t
{
public:
    phys_ptr_t() = default;

    explicit phys_ptr_t(tagged_integer_type<Storage, physical_address_tag> address) : _repr(address)
    {
    }

    explicit phys_ptr_t(T * pointer) : _repr(reinterpret_cast<Storage>(pointer) - boot_protocol::physmem_base)
    {
    }

    template<typename U>
    explicit phys_ptr_t(phys_ptr_t<U> other) : _repr(other._repr)
    {
    }

    template<typename OtherStorage>
    phys_ptr_t & operator=(
        const phys_ptr_t<T, OtherStorage> & other) requires std::is_convertible<OtherStorage, Storage>::value
    {
        _repr = tagged_integer_type<Storage, physical_address_tag>(other._repr.value());
        return *this;
    }

    T * value() const
    {
        return reinterpret_cast<T *>(_repr.value() + boot_protocol::physmem_base);
    }

    void * raw_value() const
    {
        return reinterpret_cast<void *>(_repr.value());
    }

    T * operator->() const
    {
        return value();
    }

    decltype(auto) operator*() const requires(!std::same_as<T, void>)
    {
        return *value();
    }

    explicit operator bool() const
    {
        return _repr.value();
    }

    bool operator!() const
    {
        return !_repr.value();
    }

    auto representation() const
    {
        return _repr;
    }

    phys_ptr_t operator+(std::ptrdiff_t offset)
    {
        return phys_ptr_t{ _repr + offset * sizeof(T) };
    }

    template<typename U, typename OtherStorage>
    friend class phys_ptr_t;

private:
    tagged_integer_type<Storage, physical_address_tag> _repr;
};

static_assert(sizeof(phys_ptr_t<void>) == sizeof(void *));
static_assert(sizeof(phys_ptr_t<void, std::uint32_t>) == sizeof(std::uint32_t));
}
