-- {{{ ALSA volume widget
-- Base from http://awesome.naquadah.org/wiki/Rman%27s_Simple_Volume_Widget

local alsa_channel = "Master"
local alsa_step = "5%"
local alsa_color_unmute = "#AECF96"
local alsa_color_mute = "#FF5656"
local alsa_mixer = terminal .. " -e alsamixer" -- or whatever your preferred sound mixer is

-- create widget
local alsa_widget = awful.widget.progressbar()
alsa_widget:set_width(8)
alsa_widget:set_vertical(true)
alsa_widget:set_background_color("#494B4F")
alsa_widget:set_color("#AECF96")

-- mouse bindings
alsa_widget.widget:buttons(awful.util.table.join(
    awful.button({ }, 1, function()
        awful.util.spawn(alsa_mixer)
    end),
    awful.button({ }, 3, function()
        awful.util.spawn("amixer sset " .. alsa_channel .. " toggle")
        vicious.force({ alsa_widget })
    end),
    awful.button({ }, 4, function()
        awful.util.spawn("amixer sset " .. alsa_channel .. " " .. alsa_step .. "+")
        vicious.force({ alsa_widget })
    end),
    awful.button({ }, 5, function()
        awful.util.spawn("amixer sset " .. alsa_channel .. " " .. alsa_step .. "-")
        vicious.force({ alsa_widget })
    end)
))

-- create tooltip
local alsa_widget_tip = awful.tooltip({ objects = { alsa_widget.widget }})
vicious.register(alsa_widget, vicious.widgets.volume,
    function (widget, args)
        is_muted = args[2] == "♩"
        if is_muted then
            widget:set_gradient_colors({ alsa_color_mute, alsa_color_mute, alsa_color_mute })
            alsa_widget_tip:set_text(" [Muted] ")
            return 100
        else
            current_level = args[1]
            widget:set_gradient_colors({ alsa_color_unmute, alsa_color_unmute, alsa_color_unmute })
            alsa_widget_tip:set_text(" " .. alsa_channel .. ": " .. current_level .. "% ")
            return current_level
        end
    end, 5, alsa_channel)

return alsa_widget
-- }}}
