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

#include "helpers.h"

#include <cstddef>
#include <utility>

// #include <iostream>

namespace kernel::util
{
template<typename T, typename Comparator, template<typename> typename UnboundTraits = unique_ptr_traits>
class avl_tree
{
    using Traits = UnboundTraits<T>;

    struct _tree_element : private T
    {
        static _tree_element * wrap(T * ptr)
        {
            return static_cast<_tree_element *>(ptr);
        }

        T * unwrap()
        {
            return this;
        }

        _tree_element * get_tree_parent()
        {
            return wrap(reinterpret_cast<T *>(
                reinterpret_cast<std::uintptr_t>(this->tree_parent) & ~static_cast<std::uintptr_t>(0b111)));
        }

        void set_tree_parent(_tree_element * ptr)
        {
            auto factor = get_balance_factor();
            this->tree_parent = ptr;
            set_balance_factor(factor);
        }

        std::int_least8_t get_balance_factor()
        {
            auto ret =
                reinterpret_cast<std::uintptr_t>(this->tree_parent) & static_cast<std::uintptr_t>(0b111);
            if (ret & static_cast<std::uintptr_t>(0b100))
            {
                ret |= ~static_cast<std::uintptr_t>(0b111);
            }
            return ret;
        }

        void set_balance_factor(std::int_least8_t factor)
        {
            this->tree_parent = reinterpret_cast<T *>(
                reinterpret_cast<std::uintptr_t>(get_tree_parent())
                | (static_cast<std::uintptr_t>(factor) & static_cast<std::uintptr_t>(0b111)));
        }

        _tree_element * get_left()
        {
            return wrap(this->prev);
        }

        void set_left(_tree_element * ptr)
        {
            this->prev = ptr;
        }

        _tree_element * get_right()
        {
            return wrap(this->next);
        }

        void set_right(_tree_element * ptr)
        {
            this->next = ptr;
        }
    };

    static_assert(sizeof(_tree_element) == sizeof(T));

public:
    class iterator
    {
    public:
        friend class avl_tree<T, Comparator, UnboundTraits>;

        using difference_type = std::ptrdiff_t;
        using value_type = T;
        using reference = T &;
        using iterator_category = std::bidirectional_iterator_tag;

        T & operator*() const
        {
            return *operator->();
        }

        T * operator->() const
        {
            return _element->unwrap();
        }

        iterator & operator++()
        {
            if (_element->get_right())
            {
                _element = _element->get_right();
                while (_element->get_left())
                {
                    _element = _element->get_left();
                }
                return *this;
            }

            while (_element)
            {
                auto parent = _element->get_tree_parent();
                if (parent && parent->get_left() == _element)
                {
                    _element = _element->get_tree_parent();
                    break;
                }

                _element = _element->get_tree_parent();
            }

            return *this;
        }

        iterator operator++(int)
        {
            auto copy = *this;
            ++*this;
            return copy;
        }

        iterator & operator--()
        {
            if (_element->get_left())
            {
                _element = _element->get_left();
                while (_element->get_right())
                {
                    _element = _element->get_right();
                }
                return *this;
            }

            while (_element
                   && (!_element->get_tree_parent() || _element->get_tree_parent()->get_left() == _element))
            {
                _element = _element->get_tree_parent();
            }

            return *this;
        }

        iterator operator--(int)
        {
            auto copy = *this;
            --*this;
            return copy;
        }

        friend bool operator==(iterator lhs, iterator rhs)
        {
            return lhs._element == rhs._element;
        }

    private:
        iterator(_tree_element * element) : _element(element)
        {
        }

        _tree_element * _element;
    };

    friend class iterator;

    ~avl_tree()
    {
        while (_root)
        {
            while (_root->get_left())
            {
                _rotate_right(_root);
            }

            auto old_root = _root;
            _root = old_root->get_right();

            if (!_root)
            {
                return;
            }

            _root->set_tree_parent(nullptr);
            (void)Traits::create(old_root->unwrap());
        }
    }

    iterator begin() const
    {
        if (!_root)
        {
            return iterator{ nullptr };
        }

        auto ptr = _root;
        while (ptr->get_left())
        {
            ptr = ptr->get_left();
        }
        return iterator{ ptr };
    }

    iterator end() const
    {
        return iterator{ nullptr };
    }

    std::pair<iterator, bool> insert(typename Traits::pointer element_ptr)
    {
        if (!_root)
        {
            _root = _tree_element::wrap(Traits::unwrap(std::move(element_ptr)));
            ++_size;
            return std::make_pair(iterator{ _root }, true);
        }

        auto current = _root;
        while (true)
        {
            if (_comp(*element_ptr, *current->unwrap()))
            {
                if (current->get_left())
                {
                    current = current->get_left();
                    continue;
                }

                current->set_left(_tree_element::wrap(Traits::unwrap(std::move(element_ptr))));

                current->get_left()->set_tree_parent(current);
                current = current->get_left();
                break;
            }

            if (_comp(*current->unwrap(), *element_ptr))
            {
                if (current->get_right())
                {
                    current = current->get_right();
                    continue;
                }

                current->set_right(_tree_element::wrap(Traits::unwrap(std::move(element_ptr))));

                current->get_right()->set_tree_parent(current);
                current = current->get_right();
                break;
            }

            return std::make_pair(iterator{ current }, false);
        }

        _insert_rebalance(current);
        ++_size;
        return std::make_pair(iterator{ current }, true);
    }

    iterator insert([[maybe_unused]] iterator hint, typename Traits::pointer element_ptr)
    {
        // TODO: make this actually perform better when the hint is correct
        // keeping it like this right now to allow for client code to use this once it's implemented
        return insert(std::move(element_ptr)).first;
    }

    iterator erase(T * element_ptr)
    {
        auto wrapped = _tree_element::wrap(element_ptr);
        auto ret = iterator(wrapped);
        ++ret;

        bool has_left = wrapped->get_left();
        bool has_right = wrapped->get_right();

        bool has_both = has_left && has_right;

        bool shortened_left;
        _tree_element * shortened_base = nullptr;

        if (!has_both)
        {
            auto replacement = has_left ? wrapped->get_left() : wrapped->get_right();
            if (wrapped == _root)
            {
                _root = replacement;
                if (replacement)
                {
                    replacement->set_tree_parent(nullptr);
                }
            }
            else
            {
                if (wrapped == wrapped->get_tree_parent()->get_left())
                {
                    wrapped->get_tree_parent()->set_left(replacement);
                    shortened_base = wrapped->get_tree_parent();
                    shortened_left = true;
                }
                else
                {
                    wrapped->get_tree_parent()->set_right(replacement);
                    shortened_base = wrapped->get_tree_parent();
                    shortened_left = false;
                }

                if (replacement)
                {
                    replacement->set_tree_parent(wrapped->get_tree_parent());
                }
            }
        }

        else
        {
            if (!wrapped->get_right()->get_left())
            {
                auto next = wrapped->get_right();

                if (wrapped->get_tree_parent())
                {
                    if (wrapped == wrapped->get_tree_parent()->get_left())
                    {
                        wrapped->get_tree_parent()->set_left(next);
                    }
                    else
                    {
                        wrapped->get_tree_parent()->set_right(next);
                    }
                }

                next->set_balance_factor(wrapped->get_balance_factor());
                next->set_left(wrapped->get_left());
                if (next->get_left())
                {
                    next->get_left()->set_tree_parent(next);
                }

                shortened_base = next;
                shortened_left = false;

                next->set_tree_parent(wrapped->get_tree_parent());
                if (!next->get_tree_parent())
                {
                    next->set_balance_factor(wrapped->get_balance_factor() - 1);
                    _root = next;
                    if (wrapped->get_balance_factor() < 0)
                    {
                        _rebalance_right(next);
                    }
                    shortened_base = nullptr;
                }
            }
            else
            {
                auto next = wrapped->get_right()->get_left();
                while (next->get_left())
                {
                    next = next->get_left();
                }

                if (wrapped->get_tree_parent())
                {
                    if (wrapped == wrapped->get_tree_parent()->get_left())
                    {
                        wrapped->get_tree_parent()->set_left(next);
                    }
                    else
                    {
                        wrapped->get_tree_parent()->set_right(next);
                    }
                }

                next->set_balance_factor(wrapped->get_balance_factor());

                shortened_base = next->get_tree_parent();
                shortened_left = true;

                next->get_tree_parent()->set_left(next->get_right());
                if (next->get_right())
                {
                    next->get_right()->set_tree_parent(next->get_tree_parent());
                }
                next->set_left(wrapped->get_left());
                next->get_left()->set_tree_parent(next);
                next->set_right(wrapped->get_right());
                next->get_right()->set_tree_parent(next);

                next->set_tree_parent(wrapped->get_tree_parent());
                if (!next->get_tree_parent())
                {
                    _root = next;
                }
            }
        }

        if (shortened_base)
        {
            _erase_rebalance(shortened_base, shortened_left);
        }

        Traits::create(element_ptr);
        --_size;
        return ret;
    }

    iterator erase(iterator position)
    {
        return erase(position._element->unwrap());
    }

    template<typename Key>
    iterator erase(const Key & value) requires(
        !std::same_as<Key, iterator> && !std::same_as<Key, T *> && !std::same_as<Key, const T *>)
    {
        return erase(find(value));
    }

    template<typename Key>
    iterator find(const Key & value) const
    {
        if (!_root)
        {
            return end();
        }

        auto current = _root;

        while (true)
        {
            auto less = _comp(value, *current->unwrap());
            auto greater = _comp(*current->unwrap(), value);

            if (!less && !greater)
            {
                return iterator{ current };
            }

            if (less)
            {
                if (!current->get_left())
                {
                    return end();
                }

                current = current->get_left();
                continue;
            }

            if (!current->get_right())
            {
                return end();
            }

            current = current->get_right();
        }
    }

    template<typename Key>
    iterator lower_bound(const Key & value)
    {
        if (!_root)
        {
            return end();
        }

        auto current = _root;

        while (true)
        {
            auto less = _comp(value, *current->unwrap());
            auto greater = _comp(*current->unwrap(), value);

            if (!less && !greater)
            {
                return iterator{ current };
            }

            if (less)
            {
                if (!current->get_left())
                {
                    return iterator{ current };
                }

                current = current->get_left();
                continue;
            }

            if (!current->get_right())
            {
                if (!current->get_tree_parent())
                {
                    return end();
                }

                if (current->get_tree_parent()->get_right() == current)
                {
                    return end();
                }

                current = current->get_tree_parent();

                return iterator{ current };
            }

            current = current->get_right();
        }
    }

    template<typename Key>
    iterator upper_bound(const Key & value)
    {
        auto it = lower_bound(value);
        if (it == end())
        {
            return end();
        }

        auto less = _comp(value, *it);
        auto greater = _comp(*it, value);

        if (!less && !greater) // *it == value
        {
            ++it;
        }
        return it;
    }

    auto size() const
    {
        return _size;
    }

    struct invariant_check_result
    {
        bool correct;
        std::string_view reason;
        T * offending_node;
    };

    invariant_check_result check_invariants() const
    {
        // std::cout << "====================" << std::endl;
        auto ret = _check_invariants(_root);
        // std::cout << "====================" << std::endl;
        return ret;
    }

private:
    void _insert_rebalance(_tree_element * current)
    {
        for (auto parent = current->get_tree_parent(); parent; parent = current->get_tree_parent())
        {
            if (parent->get_right() == current)
            {
                if (parent->get_balance_factor() > 0)
                {
                    if (current->get_balance_factor() < 0)
                    {
                        current = _rebalance_right_left(parent);
                    }
                    else
                    {
                        current = _rebalance_left(parent);
                    }
                    break;
                }

                else
                {
                    if (parent->get_balance_factor() < 0)
                    {
                        parent->set_balance_factor(0);
                        break;
                    }

                    parent->set_balance_factor(1);
                    current = parent;

                    continue;
                }
            }

            else // current is the left child
            {
                if (parent->get_balance_factor() < 0)
                {
                    if (current->get_balance_factor() > 0)
                    {
                        current = _rebalance_left_right(parent);
                    }
                    else
                    {
                        current = _rebalance_right(parent);
                    }
                    break;
                }

                else
                {
                    if (parent->get_balance_factor() > 0)
                    {
                        parent->set_balance_factor(0);
                        break;
                    }

                    parent->set_balance_factor(-1);
                    current = parent;

                    continue;
                }
            }
        }
    }

    void _erase_rebalance(_tree_element * current, bool shortened_left)
    {
        // "parent" is a parent of a node that moved elsewhere
        for (auto parent = current; parent; parent = current->get_tree_parent(),
                  shortened_left = (parent ? current == parent->get_left() : false))
        {
            if (shortened_left)
            {
                if (parent->get_balance_factor() > 0)
                {
                    auto right = parent->get_right();
                    auto b = right->get_balance_factor();
                    if (b < 0)
                    {
                        current = _rebalance_right_left(parent);
                    }
                    else
                    {
                        current = _rebalance_left(parent);
                    }

                    if (b == 0)
                    {
                        break;
                    }
                }

                else if (parent->get_balance_factor() == 0)
                {
                    parent->set_balance_factor(1);
                    break;
                }

                else
                {
                    current = parent;
                    current->set_balance_factor(0);
                    continue;
                }
            }

            else
            {
                if (parent->get_balance_factor() < 0)
                {
                    auto left = parent->get_left();
                    auto b = left->get_balance_factor();
                    if (b > 0)
                    {
                        current = _rebalance_left_right(parent);
                    }
                    else
                    {
                        current = _rebalance_right(parent);
                    }

                    if (b == 0)
                    {
                        break;
                    }
                }

                else if (parent->get_balance_factor() == 0)
                {
                    parent->set_balance_factor(-1);
                    break;
                }

                else
                {
                    current = parent;
                    current->set_balance_factor(0);
                    continue;
                }
            }
        }
    }

    auto _rotate_left(_tree_element * node)
    {
        auto parent = node->get_tree_parent();
        auto right = node->get_right();
        auto right_left = right->get_left();

        node->set_right(right_left);
        if (right_left)
        {
            right_left->set_tree_parent(node);
        }

        node->set_tree_parent(right);
        right->set_left(node);
        right->set_tree_parent(parent);

        if (parent)
        {
            if (parent->get_left() == node)
            {
                parent->set_left(right);
            }
            else
            {
                parent->set_right(right);
            }
        }
        else
        {
            _root = right;
        }

        return right;
    }

    auto _rotate_right(_tree_element * node)
    {
        auto parent = node->get_tree_parent();
        auto left = node->get_left();
        auto left_right = left->get_right();

        node->set_left(left_right);
        if (left_right)
        {
            left_right->set_tree_parent(node);
        }

        node->set_tree_parent(left);
        left->set_right(node);
        left->set_tree_parent(parent);

        if (parent)
        {
            if (parent->get_left() == node)
            {
                parent->set_left(left);
            }
            else
            {
                parent->set_right(left);
            }
        }
        else
        {
            _root = left;
        }

        return left;
    }

    auto _rebalance_left(_tree_element * node)
    {
        if (node->get_right()->get_balance_factor() == 0)
        {
            node->set_balance_factor(1);
            node->get_right()->set_balance_factor(-1);
        }
        else
        {
            node->set_balance_factor(0);
            node->get_right()->set_balance_factor(0);
        }

        return _rotate_left(node);
    }

    auto _rebalance_right(_tree_element * node)
    {
        if (node->get_left()->get_balance_factor() == 0)
        {
            node->set_balance_factor(-1);
            node->get_left()->set_balance_factor(1);
        }
        else
        {
            node->set_balance_factor(0);
            node->get_left()->set_balance_factor(0);
        }

        return _rotate_right(node);
    }

    auto _rebalance_left_right(_tree_element * node)
    {
        auto bf = node->get_left()->get_right()->get_balance_factor();
        if (bf == 0)
        {
            node->set_balance_factor(0);
            node->get_left()->set_balance_factor(0);
        }
        else if (bf < 0)
        {
            node->set_balance_factor(1);
            node->get_left()->set_balance_factor(0);
        }
        else
        {
            node->set_balance_factor(0);
            node->get_left()->set_balance_factor(-1);
        }

        _rotate_left(node->get_left());
        auto ret = _rotate_right(node);
        ret->set_balance_factor(0);
        return ret;
    }

    auto _rebalance_right_left(_tree_element * node)
    {
        auto bf = node->get_right()->get_left()->get_balance_factor();
        if (bf == 0)
        {
            node->set_balance_factor(0);
            node->get_right()->set_balance_factor(0);
        }
        else if (bf > 0)
        {
            node->set_balance_factor(-1);
            node->get_right()->set_balance_factor(0);
        }
        else
        {
            node->set_balance_factor(0);
            node->get_right()->set_balance_factor(1);
        }

        _rotate_right(node->get_right());
        auto ret = _rotate_left(node);
        ret->set_balance_factor(0);
        return ret;
    }

    invariant_check_result _check_invariants(_tree_element * node) const
    {
        if (!node)
        {
            return { true, "", nullptr };
        }

        if (auto left = node->get_left())
        {
            if (left->get_tree_parent() != node)
            {
                return { false, "left child does not have a correct parent link", node->unwrap() };
            }
        }

        if (auto right = node->get_right())
        {
            if (right->get_tree_parent() != node)
            {
                return { false, "right child does not have a correct parent link", node->unwrap() };
            }
        }

        auto bf = node->get_balance_factor();

        auto left_depth = _left_depth(node);
        auto right_depth = _right_depth(node);
        auto real_bf = right_depth - left_depth;

        // std::cout << "node: " << node->unwrap()->id << std::endl;
        // std::cout << "bf: " << (int)bf << std::endl;
        // std::cout << "left: " << (node->get_left() ? std::to_string(node->get_left()->unwrap()->id) :
        // "(nil)")
        // << std::endl;
        // std::cout << "left depth: " << left_depth << std::endl;
        // std::cout << "right: "
        // << (node->get_right() ? std::to_string(node->get_right()->unwrap()->id) : "(nil)")
        // << std::endl;
        // std::cout << "right depth: " << right_depth << std::endl;
        // std::cout << "real bf: " << real_bf << std::endl << std::endl;

        if (bf != real_bf)
        {
            return { false, "node's balance factor wasn't equal to actual depth difference", node->unwrap() };
        }

        if (bf < -1 || bf > 1)
        {
            return { false, "node's balance factor was outside of allowed values", node->unwrap() };
        }

        if (auto left = node->get_left())
        {
            if (!_comp(*left->unwrap(), *node->unwrap()))
            {
                return { false, "left child was not lesser than a node", node->unwrap() };
            }

            auto ret = _check_invariants(left);
            if (!ret.correct)
            {
                return ret;
            }
        }

        if (auto right = node->get_right())
        {
            if (!_comp(*node->unwrap(), *right->unwrap()))
            {
                return { false, "left child was not lesser than a node", node->unwrap() };
            }

            auto ret = _check_invariants(right);
            if (!ret.correct)
            {
                return ret;
            }
        }

        return { true, "", nullptr };
    }

    std::ptrdiff_t _left_depth(_tree_element * node) const
    {
        auto left = node->get_left();
        if (!left)
        {
            return 0;
        }

        auto left_depth = _left_depth(left);
        auto right_depth = _right_depth(left);

        return (left_depth > right_depth ? left_depth : right_depth) + 1;
    }

    std::ptrdiff_t _right_depth(_tree_element * node) const
    {
        auto right = node->get_right();
        if (!right)
        {
            return 0;
        }

        auto left_depth = _left_depth(right);
        auto right_depth = _right_depth(right);

        return (left_depth > right_depth ? left_depth : right_depth) + 1;
    }

    _tree_element * _root = nullptr;
    std::size_t _size = 0;
    Comparator _comp;
};
}
