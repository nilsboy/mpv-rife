-- Toggle RIFE frame interpolation at runtime.
--
-- Adds or removes the vapoursynth filter bound to the bundled rife.vpy script.
-- Configure with script-opts, e.g. in mpv.conf:
--   script-opts=rife-toggle-vpy=/path/to/rife.vpy
-- or in script-opts/rife-toggle.conf:
--   vpy=/path/to/rife.vpy

local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"
local opts = require "mp.options"

local options = {
    vpy = "",
    label = "rife",
}

opts.read_options(options, "rife-toggle")

local enabled = false

local function script_path()
    local info = debug.getinfo(1, "S")
    local dir = info.source:match("@?(.*/)")
    return dir or "./"
end

local function resolve_vpy()
    if options.vpy ~= "" then
        return options.vpy
    end
    -- Default to vapoursynth/rife.vpy at the root of the repo or snap.
    return utils.join_path(script_path(), "../../vapoursynth/rife.vpy")
end

local function toggle()
    if enabled then
        mp.commandv("vf", "remove", "@" .. options.label)
        enabled = false
        mp.osd_message("RIFE: off")
        return
    end

    local vpy = resolve_vpy()
    if not utils.file_info(vpy) then
        msg.error("rife.vpy not found: " .. vpy)
        mp.osd_message("RIFE: script not found", 3)
        return
    end

    mp.commandv("vf", "add", "@" .. options.label .. ":vapoursynth=" .. vpy)
    enabled = true
    mp.osd_message("RIFE: on")
end

mp.add_key_binding(nil, "toggle-rife", toggle)
mp.register_script_message("toggle-rife", toggle)
