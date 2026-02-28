-- kostats.koplugin/main.lua

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local KoStats = WidgetContainer:extend{
    name = "kostats",
    is_doc_only = false,
}

function KoStats:init()
    self.ui.menu:registerToMainMenu(self)
    self:scheduleAutoUpload()
end

function KoStats:onSuspend()
    self:checkAndUploadDaily()
end

function KoStats:onResume()
    self:checkAndUploadDaily()
end

function KoStats:onCloseDocument()
    self:checkAndUploadDaily()
end

function KoStats:scheduleAutoUpload()
    self:checkAndUploadDaily()
end

function KoStats:checkAndUploadDaily()
    local auto_upload_enabled = G_reader_settings:readSetting("kostats_auto_upload")
    if auto_upload_enabled == false then return end

    local last_upload = G_reader_settings:readSetting("kostats_last_upload_date")
    local today = os.date("%Y-%m-%d")

    if last_upload ~= today then
        logger.info("KoStats: Automatic daily upload triggered")
        self:uploadStatistics(true)
        local include_annotations = G_reader_settings:readSetting("kostats_include_annotations")
        if include_annotations ~= false then
            self:uploadAnnotations(true)
        end
    end
end

function KoStats:addToMainMenu(menu_items)
    menu_items.kostats = {
        text = _("Upload Statistics"),
        sub_item_table = {
            {
                text = _("Upload Statistics Now"),
                callback = function()
                    self:uploadStatistics(false)
                end,
            },
            {
                text = _("Upload Highlights & Annotations Now"),
                callback = function()
                    self:uploadAnnotations(false)
                end,
            },
            {
                text = _("Settings"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = _("Server URL"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerURL()
                        end,
                    },
                    {
                        text = _("Secret Key"),
                        keep_menu_open = true,
                        callback = function()
                            self:editSecretKey()
                        end,
                    },
                    {
                        text = _("Scan folder for highlights"),
                        keep_menu_open = true,
                        callback = function()
                            self:editScanPath()
                        end,
                    },
                    {
                        text = _("Automatic daily upload"),
                        checked_func = function()
                            return G_reader_settings:readSetting("kostats_auto_upload") ~= false
                        end,
                        callback = function()
                            local current = G_reader_settings:readSetting("kostats_auto_upload")
                            if current == false then
                                G_reader_settings:saveSetting("kostats_auto_upload", true)
                                UIManager:show(InfoMessage:new{
                                    text = _("Automatic daily upload enabled"),
                                    timeout = 2,
                                })
                            else
                                G_reader_settings:saveSetting("kostats_auto_upload", false)
                                UIManager:show(InfoMessage:new{
                                    text = _("Automatic daily upload disabled"),
                                    timeout = 2,
                                })
                            end
                        end,
                    },
                    {
                        text = _("Include highlights & annotations in sync"),
                        checked_func = function()
                            return G_reader_settings:readSetting("kostats_include_annotations") ~= false
                        end,
                        callback = function()
                            local current = G_reader_settings:readSetting("kostats_include_annotations")
                            if current == false then
                                G_reader_settings:saveSetting("kostats_include_annotations", true)
                                UIManager:show(InfoMessage:new{
                                    text = _("Highlights & annotations will be included in sync"),
                                    timeout = 2,
                                })
                            else
                                G_reader_settings:saveSetting("kostats_include_annotations", false)
                                UIManager:show(InfoMessage:new{
                                    text = _("Highlights & annotations excluded from sync"),
                                    timeout = 2,
                                })
                            end
                        end,
                        separator = true,
                    },
                    {
                        text_func = function()
                            local last_upload = G_reader_settings:readSetting("kostats_last_upload_date")
                            if last_upload then
                                return T(_("Last upload: %1"), last_upload)
                            else
                                return _("Last upload: never")
                            end
                        end,
                        enabled = false,
                    },
                },
            },
        },
    }
end

function KoStats:editServerURL()
    local current_url = G_reader_settings:readSetting("kostats_server_url") or "https://thepixelpro.de/KoStats/upload.php"

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Server URL"),
        input = current_url,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_url = input_dialog:getInputText()
                        G_reader_settings:saveSetting("kostats_server_url", new_url)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Server URL saved"),
                            timeout = 2,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function KoStats:editSecretKey()
    local current_key = G_reader_settings:readSetting("kostats_secret_key") or ""

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Secret Key"),
        input = current_key,
        input_type = "text",
        text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_key = input_dialog:getInputText()
                        G_reader_settings:saveSetting("kostats_secret_key", new_key)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Secret key saved"),
                            timeout = 2,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function KoStats:editScanPath()
    local default_path = "/mnt/onboard/"
    local current_path = G_reader_settings:readSetting("kostats_scan_path") or default_path

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Scan folder for highlights"),
        input = current_path,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Reset"),
                    callback = function()
                        G_reader_settings:saveSetting("kostats_scan_path", default_path)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Scan path reset to: %1"), default_path),
                            timeout = 2,
                        })
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_path = input_dialog:getInputText()
                        if new_path:sub(-1) ~= "/" then
                            new_path = new_path .. "/"
                        end
                        G_reader_settings:saveSetting("kostats_scan_path", new_path)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Scan path saved: %1"), new_path),
                            timeout = 2,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function KoStats:uploadStatistics(silent)
    local server_url = G_reader_settings:readSetting("kostats_server_url")
    local secret_key = G_reader_settings:readSetting("kostats_secret_key")

    if not server_url or server_url == "" then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Please configure server URL in settings first"),
                timeout = 3,
            })
        end
        return
    end

    if not secret_key or secret_key == "" then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Please configure secret key in settings first"),
                timeout = 3,
            })
        end
        return
    end

    if not silent then
        UIManager:show(InfoMessage:new{
            text = _("Uploading statistics..."),
            timeout = 2,
        })
    end

    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

    local file = io.open(db_location, "rb")
    if not file then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Statistics database not found at: " .. db_location),
                timeout = 5,
            })
        end
        logger.warn("KoStats: Database not found at:", db_location)
        return
    end

    local content = file:read("*all")
    file:close()

    logger.info("KoStats: Starting upload, DB size:", #content, "bytes", silent and "(auto)" or "(manual)")

    local socketutil = require("socketutil")
    socketutil:set_timeout(30, 30)

    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local boundary = "----KOReaderBoundary" .. os.time()
    local body_parts = {}

    table.insert(body_parts, "--" .. boundary .. "\r\n")
    table.insert(body_parts, 'Content-Disposition: form-data; name="key"\r\n\r\n')
    table.insert(body_parts, secret_key .. "\r\n")

    table.insert(body_parts, "--" .. boundary .. "\r\n")
    table.insert(body_parts, 'Content-Disposition: form-data; name="database"; filename="statistics.sqlite3"\r\n')
    table.insert(body_parts, "Content-Type: application/octet-stream\r\n\r\n")
    table.insert(body_parts, content .. "\r\n")
    table.insert(body_parts, "--" .. boundary .. "--\r\n")

    local body = table.concat(body_parts)

    local response_body = {}
    local res, code = http.request{
        url = server_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
            ["Content-Length"] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_body),
    }

    if res and code == 200 then
        G_reader_settings:saveSetting("kostats_last_upload_date", os.date("%Y-%m-%d"))
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Statistics uploaded successfully!"),
                timeout = 3,
            })
        end
        logger.info("KoStats: Upload successful")
    else
        local response_text = table.concat(response_body)
        if not silent then
            UIManager:show(InfoMessage:new{
                text = T(_("Upload failed: %1"), tostring(code or "connection error")),
                timeout = 5,
            })
        end
        logger.warn("KoStats: Upload failed with code:", code, "Response:", response_text)
    end
end

function KoStats:uploadAnnotations(silent)
    local server_url = G_reader_settings:readSetting("kostats_server_url")
    local secret_key = G_reader_settings:readSetting("kostats_secret_key")

    if not server_url or server_url == "" then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Please configure server URL in settings first"),
                timeout = 3,
            })
        end
        return
    end

    if not secret_key or secret_key == "" then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Please configure secret key in settings first"),
                timeout = 3,
            })
        end
        return
    end

    if not silent then
        UIManager:show(InfoMessage:new{
            text = _("Scanning for highlights & annotations..."),
            timeout = 2,
        })
    end

    local annotations_url = server_url:gsub("upload%.php$", "upload_annotations.php")
    if annotations_url == server_url then
        annotations_url = server_url .. "_annotations"
    end

    local scan_path = G_reader_settings:readSetting("kostats_scan_path") or "/mnt/onboard/"
    local annotations = {}

    local function escape_json(s)
        s = tostring(s or "")
        s = s:gsub('\\', '\\\\')
        s = s:gsub('"',  '\\"')
        s = s:gsub('\n', '\\n')
        s = s:gsub('\r', '\\r')
        s = s:gsub('\t', '\\t')
        return s
    end

    -- Use 'find' shell command to locate all metadata.*.lua files inside .sdr folders
    -- This avoids needing the lfs module entirely
    local find_cmd = string.format(
        'find %q -type f -name "metadata.*.lua" 2>/dev/null',
        scan_path
    )

    logger.info("KoStats: Running:", find_cmd)

    local pipe = io.popen(find_cmd)
    if not pipe then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("Failed to scan for highlight files"),
                timeout = 3,
            })
        end
        return
    end

    local lua_files = {}
    for line in pipe:lines() do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(lua_files, trimmed)
        end
    end
    pipe:close()

    logger.info("KoStats: Found", #lua_files, ".lua metadata files")

    for _, lua_path in ipairs(lua_files) do
        local ok_load, book_data = pcall(dofile, lua_path)

        if ok_load and type(book_data) == "table" then
            local doc_props = book_data["doc_props"] or {}
            local book_annotations = book_data["annotations"] or {}

            for _, ann in pairs(book_annotations) do
                -- Only real highlights have pos1
                if ann["pos1"] then
                    table.insert(annotations, {
                        book_title    = doc_props["title"]    or "",
                        book_authors  = doc_props["authors"]  or "",
                        book_language = doc_props["language"] or "",
                        text          = ann["text"]     or "",
                        chapter       = ann["chapter"]  or "",
                        pageno        = ann["pageno"]   or 0,
                        datetime      = ann["datetime"] or "",
                        color         = ann["color"]    or "",
                        drawer        = ann["drawer"]   or "",
                        pos0          = ann["pos0"]     or "",
                        pos1          = ann["pos1"]     or "",
                    })
                end
            end
        else
            logger.warn("KoStats: Failed to load:", lua_path, ok_load, book_data)
        end
    end

    if #annotations == 0 then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = _("No highlights found to upload"),
                timeout = 3,
            })
        end
        logger.info("KoStats: No annotations found in:", scan_path)
        return
    end

    logger.info("KoStats: Found", #annotations, "highlights")

    -- Build JSON manually
    local json_parts = {'{"annotations":['}
    for i, ann in ipairs(annotations) do
        local entry = string.format(
            '{"book_title":"%s","book_authors":"%s","book_language":"%s",' ..
            '"text":"%s","chapter":"%s","pageno":%d,"datetime":"%s",' ..
            '"color":"%s","drawer":"%s","pos0":"%s","pos1":"%s"}',
            escape_json(ann.book_title),
            escape_json(ann.book_authors),
            escape_json(ann.book_language),
            escape_json(ann.text),
            escape_json(ann.chapter),
            ann.pageno,
            escape_json(ann.datetime),
            escape_json(ann.color),
            escape_json(ann.drawer),
            escape_json(ann.pos0),
            escape_json(ann.pos1)
        )
        table.insert(json_parts, entry)
        if i < #annotations then
            table.insert(json_parts, ",")
        end
    end
    table.insert(json_parts, "]}")

    local json_body = table.concat(json_parts)

    local socketutil = require("socketutil")
    socketutil:set_timeout(30, 30)

    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local boundary = "----KOReaderBoundary" .. os.time()
    local body_parts = {}

    table.insert(body_parts, "--" .. boundary .. "\r\n")
    table.insert(body_parts, 'Content-Disposition: form-data; name="key"\r\n\r\n')
    table.insert(body_parts, secret_key .. "\r\n")

    table.insert(body_parts, "--" .. boundary .. "\r\n")
    table.insert(body_parts, 'Content-Disposition: form-data; name="annotations"; filename="annotations.json"\r\n')
    table.insert(body_parts, "Content-Type: application/json\r\n\r\n")
    table.insert(body_parts, json_body .. "\r\n")
    table.insert(body_parts, "--" .. boundary .. "--\r\n")

    local body = table.concat(body_parts)

    logger.info("KoStats: Uploading", #annotations, "annotations to:", annotations_url)

    local response_body = {}
    local res, code = http.request{
        url = annotations_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
            ["Content-Length"] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_body),
    }

    if res and code == 200 then
        if not silent then
            UIManager:show(InfoMessage:new{
                text = T(_("Uploaded %1 highlights successfully!"), tostring(#annotations)),
                timeout = 3,
            })
        end
        logger.info("KoStats: Annotation upload successful,", #annotations, "items")
    else
        local response_text = table.concat(response_body)
        if not silent then
            UIManager:show(InfoMessage:new{
                text = T(_("Annotation upload failed: %1"), tostring(code or "connection error")),
                timeout = 5,
            })
        end
        logger.warn("KoStats: Annotation upload failed, code:", code, "Response:", response_text)
    end
end

return KoStats
