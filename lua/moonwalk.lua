-- Copyright (C) 2021 Gregory Anders
--
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local cachedir = vim.fn.stdpath("cache")

local log = (function()
    local logfile = assert(io.open(cachedir .. "/moonwalk.log", "a"))
    return function(msg)
        logfile:write(string.format("[%s] %s\n", os.date("%F %T"), msg))
        logfile:flush()
    end
end)()

-- TODO: Rewrite this when autocommands are supported natively in Lua
local function setup_autocmds(ext)
    vim.cmd(string.format(
        [[
augroup moonwalk_%s
    autocmd!
    autocmd SourceCmd *.%s lua require("moonwalk")._source()
    autocmd FileType * ++nested lua require("moonwalk")._load_ftplugin('%s')
augroup END]],
        ext,
        ext,
        ext
    ))
end

local M = {}

M.compilers = {}

function M.add_loader(ext, compile, opts)
    M.compilers[ext] = function(path)
        local luapath = cachedir .. "/moonwalk" .. path:gsub("%." .. ext .. "$", ".lua")
        local s = vim.loop.fs_stat(luapath)
        if not s or vim.loop.fs_stat(path).mtime.sec > s.mtime.sec then
            local src = assert(io.open(path, "r"))
            local input = src:read("*a")
            src:close()

            local ok, output = pcall(compile, input)
            if not ok then
                local msg = string.format("%s: %s", path, output)
                log(msg)
                error(msg, 0)
            end

            vim.fn.mkdir(luapath:match("(.+)/.-%.lua"), "p")

            local dst = assert(io.open(luapath, "w"))
            dst:write(output)
            dst:close()
            log(string.format("Compiled %s to %s", path, luapath))
        end
        return luapath
    end

    local function loader(name)
        local basename = name:gsub("%.", "/")
        opts = opts or {}
        local dir = opts.dir or ext
        local paths = { dir .. "/" .. basename .. "." .. ext, dir .. "/" .. basename .. "/init." .. ext }
        for _, path in ipairs(paths) do
            local found = vim.api.nvim_get_runtime_file(path, false)
            if #found > 0 then
                local luafile = M.compilers[ext](found[1])
                local f, err = loadfile(luafile)
                return f or error(err)
            end
        end
    end

    table.insert(package.loaders, loader)

    setup_autocmds(ext)
end

function M._load_ftplugin(ext)
    local s = vim.fn.expand("<amatch>")
    for name in vim.gsplit(s or "", ".", true) do
        if name then
            vim.api.nvim_command(
                string.format(
                    "runtime! ftplugin/%s.%s ftplugin/%s_*.%s ftplugin/%s/*.%s",
                    name,
                    ext,
                    name,
                    ext,
                    name,
                    ext
                )
            )
        end
    end
end

function M._source()
    local path = vim.fn.expand("<afile>")
    if not path or path == "" then
        return
    end

    local ext = path:match("[^/.]%.(.-)$")
    local ok, result = pcall(M.compilers[ext], path)
    if ok then
        vim.api.nvim_command("source " .. result)
    else
        vim.notify(result, vim.log.levels.ERROR)
    end
end

return M
