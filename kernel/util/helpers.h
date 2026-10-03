/*
 * Copyright © 2022 Michał 'Griwes' Dominiak
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

#include <memory>

#include "chained_allocator.h"

namespace kernel::util
{
template<typename T>
struct treeable : chained_allocatable<T>
{
    T * tree_parent = nullptr;
};

template<typename T>
struct unique_ptr_traits
{
    using pointer = std::unique_ptr<T>;

    static auto create(T * pointer)
    {
        return std::unique_ptr<T>(pointer);
    }

    static auto unwrap(std::unique_ptr<T> pointer)
    {
        return pointer.release();
    }
};
}
