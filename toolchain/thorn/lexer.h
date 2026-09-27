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

#include "util.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <unordered_map>

namespace thorn::lexer
{
enum class token_type
{
    syscall,
    enum_,
    struct_,
    union_,
    open_paren,
    close_paren,
    colon,
    comma,
    semicolon,
    scope,
    token,
    permissions,
    for_,
    direction,
    ptr,
    identifier,
    arrow,
    dollar,
    include,
    header_name,
    blocking
};

inline const std::unordered_map<token_type, std::string> descriptions = {
    { token_type::syscall, "'syscall'" },  { token_type::enum_, "'enum'" },
    { token_type::struct_, "'struct'" },   { token_type::union_, "'union'" },
    { token_type::open_paren, "'('" },     { token_type::close_paren, "')'" },
    { token_type::colon, "':'" },          { token_type::comma, "','" },
    { token_type::semicolon, "';'" },      { token_type::scope, "'::'" },
    { token_type::token, "'token'" },      { token_type::permissions, "'permissions'" },
    { token_type::for_, "'for'" },         { token_type::direction, "direction-specifier" },
    { token_type::ptr, "'ptr'" },          { token_type::identifier, "identifier" },
    { token_type::arrow, "'->'" },         { token_type::dollar, "'$'" },
    { token_type::include, "'include'" },  { token_type::header_name, "header-name" },
    { token_type::blocking, "'blocking'" }
};

inline const std::unordered_map<char, token_type> symbol_types = { { '(', token_type::open_paren },
                                                                   { ')', token_type::close_paren },
                                                                   { ',', token_type::comma },
                                                                   { ';', token_type::semicolon },
                                                                   { '$', token_type::dollar } };

inline const std::unordered_map<std::string, token_type> keywords = {
    { "syscall", token_type::syscall }, { "enum", token_type::enum_ },
    { "struct", token_type::struct_ },  { "union", token_type::union_ },
    { "token", token_type::token },     { "permissions", token_type::permissions },
    { "for", token_type::for_ },        { "in", token_type::direction },
    { "out", token_type::direction },   { "ptr", token_type::ptr },
    { "include", token_type::include }, { "blocking", token_type::blocking }
};

struct token
{
    std::uintptr_t line = 0;
    std::uintptr_t column = 0;
    std::string contents;
    token_type type;
};

struct tokenizer_sentinel
{
};

struct tokenizer_iterator
{
    tokenizer_iterator(std::filesystem::path filename) : _filename(filename), _input(_filename)
    {
        if (!_input.good())
        {
            std::cerr << "thorn: failed to open input file " << _filename << std::endl;
            std::exit(1);
        }

        _generate();
    }

    bool operator==(tokenizer_sentinel)
    {
        return _input.eof();
    }

    void operator++()
    {
        _generate();
    }

    auto operator*() const
    {
        return _current;
    }

    auto operator->() const
    {
        return &_current;
    }

private:
    void _generate()
    {
        while (std::isspace(_peek()))
        {
            _get();
        }

        if (_input.eof())
        {
            return;
        }

        _current.line = _line;
        _current.column = _column;
        _current.contents.clear();

        if (_peek() == ':')
        {
            _append();
            _current.type = token_type::colon;
            if (_peek() == ':')
            {
                _append();
                _current.type = token_type::scope;
            }
            return;
        }

        if (_peek() == '-')
        {
            _append();
            if (_peek() != '>')
            {
                REPORT_ERROR(_filename, _line, _column, "expected '>', got " << _peek());
            }
            _append();
            _current.type = token_type::arrow;
            return;
        }

        if (_peek() == '<')
        {
            _get();
            while (_peek() != '>')
            {
                if (_input.eof())
                {
                    REPORT_ERROR(_filename, _line, _column, "unternimated header-name");
                }
                _append();
            }
            _current.type = token_type::header_name;
            _get();
            return;
        }

        if (symbol_types.contains(_peek()))
        {
            _append();
            _current.type = symbol_types.at(_current.contents.back());
            return;
        }

        if (std::isalpha(_peek()))
        {
            _append();
            while (std::isalnum(_peek()) || _peek() == '_')
            {
                _append();
            }
            auto it = keywords.find(_current.contents);
            _current.type = (it == keywords.end()) ? token_type::identifier : it->second;
            return;
        }

        REPORT_ERROR(_filename, _line, _column, "unexpected character: '" << _peek() << "'");
    }

    char _peek()
    {
        return _input.peek();
    }

    char _get()
    {
        auto ret = _input.get();
        if (ret == '\n')
        {
            ++_line;
            _column = 1;
        }
        else
        {
            ++_column;
        }
        return ret;
    }

    void _append()
    {
        _current.contents.push_back(_get());
    }

    std::filesystem::path _filename;
    std::ifstream _input;
    token _current;

    std::uintptr_t _line = 1;
    std::uintptr_t _column = 1;
};

inline tokenizer_iterator tokenize(std::filesystem::path input)
{
    return { std::move(input) };
}
}
