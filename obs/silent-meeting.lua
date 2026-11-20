local obs = obslua
local filter = {
    id = "silent_meeting_film",
    type = obs.OBS_SOURCE_TYPE_FILTER,
    output_flags = obs.OBS_SOURCE_VIDEO,
}

local FRESH_SECONDS = 20
local MAX_PAGES = 12
local POLL_SECONDS = 0.125

local function text_length(text)
    local _, characters = text:gsub("[^\128-\191]", "")
    return characters
end

local function default_font()
    if jit.os == "Linux" or jit.os == "BSD" then
        return "DejaVu Serif"
    end
    return "Georgia"
end

function filter.get_name()
    return "Silent Meeting"
end

function filter.get_defaults(settings)
    obs.obs_data_set_default_string(settings, "dialogue", script_path() .. "../.runtime/dialogue.tsv")
    obs.obs_data_set_default_string(settings, "font", default_font())
    obs.obs_data_set_default_double(settings, "wear", 0.65)
    obs.obs_data_set_default_double(settings, "hold", 2.5)
end

function filter.get_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_path(props, "dialogue", "Dialogue file", obs.OBS_PATH_FILE, "TSV (*.tsv)", nil)
    obs.obs_properties_add_text(props, "font", "Dialogue font family", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_float_slider(props, "wear", "Film wear", 0, 1, 0.01)
    obs.obs_properties_add_float_slider(props, "hold", "Minimum card duration (seconds)", 1, 6, 0.1)
    return props
end

local function set_text(data, text)
    local settings = obs.obs_data_create()
    local font = obs.obs_data_create()
    obs.obs_data_set_string(font, "face", data.font)
    obs.obs_data_set_int(font, "size", 96)
    obs.obs_data_set_obj(settings, "font", font)
    obs.obs_data_set_int(settings, "custom_width", text_length(text) > 44 and 1480 or 0)
    obs.obs_data_set_bool(settings, "word_wrap", true)
    obs.obs_data_set_int(settings, "color1", 0xffeeeae1)
    obs.obs_data_set_int(settings, "color2", 0xffeeeae1)
    obs.obs_data_set_string(settings, "text", text)
    obs.obs_source_update(data.title, settings)
    obs.obs_data_release(font)
    obs.obs_data_release(settings)
end

function filter.update(data, settings)
    local path = obs.obs_data_get_string(settings, "dialogue")
    if data.path ~= path then
        data.path = path
        data.seen = {}
        data.pages = {}
        data.remaining = 0
    end
    local font = obs.obs_data_get_string(settings, "font")
    data.font = font ~= "" and font or default_font()
    data.wear = obs.obs_data_get_double(settings, "wear")
    data.hold = obs.obs_data_get_double(settings, "hold")
    if data.title then
        set_text(data, data.text)
    end
end

function filter.create(settings, source)
    local data = {source = source, clock = 0, poll = 0, remaining = 0, text = ""}
    data.title = obs.obs_source_create_private("text_ft2_source_v2", "Silent Meeting dialogue", nil)
    obs.obs_enter_graphics()
    data.effect = obs.gs_effect_create_from_file(script_path() .. "silent-film.effect", nil)
    obs.obs_leave_graphics()
    if data.effect then
        data.time_param = obs.gs_effect_get_param_by_name(data.effect, "clock_time")
        data.wear_param = obs.gs_effect_get_param_by_name(data.effect, "wear")
        data.card_param = obs.gs_effect_get_param_by_name(data.effect, "card")
        data.aspect_param = obs.gs_effect_get_param_by_name(data.effect, "aspect_ratio")
    else
        obs.script_log(obs.LOG_ERROR, "Silent Meeting could not load silent-film.effect.")
    end
    if not data.title then
        obs.script_log(obs.LOG_ERROR, "Silent Meeting requires OBS Text (FreeType 2) for dialogue.")
    end
    filter.update(data, settings)
    return data
end

function filter.destroy(data)
    if data.title then
        obs.obs_source_release(data.title)
    end
    if data.effect then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(data.effect)
        obs.obs_leave_graphics()
    end
end

local function poll_dialogue(data)
    local stream = io.open(data.path, "rb")
    if not stream then
        return
    end
    local snapshot = stream:read(16384)
    stream:close()
    if not snapshot then
        data.pages = {}
        return
    end

    local now = os.time()
    local seen = {}
    for line in snapshot:gmatch("[^\r\n]+") do
        local timestamp, key, text = line:match("^(%d+)\t([%w%-]+)\t(.+)$")
        local age = timestamp and now - tonumber(timestamp)
        if age and age >= -2 and age < FRESH_SECONDS then
            seen[key] = true
            if not data.seen[key] then
                if #data.pages == MAX_PAGES then
                    table.remove(data.pages, 1)
                end
                data.pages[#data.pages + 1] = {text = text, timestamp = tonumber(timestamp)}
            end
        end
    end
    data.seen = seen
end

function filter.video_tick(data, seconds)
    data.clock = (data.clock + seconds) % 120
    if not data.title then
        return
    end
    data.remaining = math.max(0, data.remaining - seconds)
    data.poll = data.poll - seconds
    if data.poll <= 0 then
        data.poll = POLL_SECONDS
        poll_dialogue(data)
    end
    if data.remaining == 0 then
        local now = os.time()
        while #data.pages > 0 do
            local page = table.remove(data.pages, 1)
            if now - page.timestamp < FRESH_SECONDS then
                data.text = page.text
                set_text(data, page.text)
                data.remaining = math.max(data.hold, math.min(7, text_length(page.text) / 17))
                break
            end
        end
    end
end

function filter.get_width(data)
    local target = obs.obs_filter_get_target(data.source)
    return target and obs.obs_source_get_base_width(target) or 0
end

function filter.get_height(data)
    local target = obs.obs_filter_get_target(data.source)
    return target and obs.obs_source_get_base_height(target) or 0
end

function filter.video_render(data)
    local width = filter.get_width(data)
    local height = filter.get_height(data)
    if not data.effect or width == 0 or height == 0 then
        obs.obs_source_skip_video_filter(data.source)
        return
    end
    if not obs.obs_source_process_filter_begin(data.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING) then
        return
    end

    local tw = data.title and obs.obs_source_get_width(data.title) or 0
    local th = data.title and obs.obs_source_get_height(data.title) or 0
    local show_card = data.remaining > 0 and tw > 0 and th > 0
    obs.gs_effect_set_float(data.time_param, data.clock)
    obs.gs_effect_set_float(data.wear_param, data.wear)
    obs.gs_effect_set_float(data.card_param, show_card and 1 or 0)
    obs.gs_effect_set_float(data.aspect_param, width / height)
    obs.obs_source_process_filter_end(data.source, data.effect, width, height)

    if show_card then
        local scale = math.min(width * 0.73 / tw, height * 0.49 / th, height * 0.069 / 96)
        obs.gs_matrix_push()
        obs.gs_matrix_translate3f((width - scale * tw) * 0.5, (height - scale * th) * 0.5, 0)
        obs.gs_matrix_scale3f(scale, scale, 1)
        obs.obs_source_video_render(data.title)
        obs.gs_matrix_pop()
    end
end

function script_description()
    return "Adds the Silent Meeting camera filter. Run the Silent Meeting microphone companion for dialogue cards."
end

obs.obs_register_source(filter)
