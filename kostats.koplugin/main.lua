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
    -- Versuche Upload beim Suspend (Gerät geht schlafen)
    self:checkAndUploadDaily()
end

function KoStats:onResume()
    -- Prüfe beim Aufwachen ob Upload fällig ist
    self:checkAndUploadDaily()
end

function KoStats:onCloseDocument()
    -- Prüfe beim Schließen eines Dokuments
    self:checkAndUploadDaily()
end

function KoStats:scheduleAutoUpload()
    -- Prüfe beim Start ob Upload fällig ist
    self:checkAndUploadDaily()
end

function KoStats:checkAndUploadDaily()
    local auto_upload_enabled = G_reader_settings:readSetting("kostats_auto_upload")
    
    -- Wenn Auto-Upload deaktiviert ist, nichts tun
    if auto_upload_enabled == false then
        return
    end
    
    -- Standard: Auto-Upload ist aktiviert (außer explizit deaktiviert)
    local last_upload = G_reader_settings:readSetting("kostats_last_upload_date")
    local today = os.date("%Y-%m-%d")
    
    -- Wenn heute noch nicht hochgeladen wurde
    if last_upload ~= today then
        logger.info("KoStats: Automatic daily upload triggered")
        self:uploadStatistics(true) -- true = silent (keine Popup-Nachrichten)
    end
end

function KoStats:addToMainMenu(menu_items)
    menu_items.kostats = {
        text = _("Upload Statistics"),
        sub_item_table = {
            {
                text = _("Upload Now"),
                callback = function()
                    self:uploadStatistics(false) -- false = nicht silent (zeige Nachrichten)
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
    
    -- Finde die statistics.sqlite3 Datei
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    
    -- Prüfe ob Datei existiert
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
    
    -- Führe Upload durch
    local socketutil = require("socketutil")
    socketutil:set_timeout(30, 30)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    -- Erstelle Multipart Form Data
    local boundary = "----KOReaderBoundary" .. os.time()
    local body_parts = {}
    
    -- Secret Key Teil
    table.insert(body_parts, "--" .. boundary .. "\r\n")
    table.insert(body_parts, 'Content-Disposition: form-data; name="key"\r\n\r\n')
    table.insert(body_parts, secret_key .. "\r\n")
    
    -- Datei Teil
    table.insert(body_parts, "--" .. boundary .. "\r\n")
    table.insert(body_parts, 'Content-Disposition: form-data; name="database"; filename="statistics.sqlite3"\r\n')
    table.insert(body_parts, "Content-Type: application/octet-stream\r\n\r\n")
    table.insert(body_parts, content .. "\r\n")
    table.insert(body_parts, "--" .. boundary .. "--\r\n")
    
    local body = table.concat(body_parts)
    
    logger.info("KoStats: Uploading to:", server_url)
    
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
        -- Speichere Datum des erfolgreichen Uploads
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

return KoStats