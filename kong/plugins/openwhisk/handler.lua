local BasePlugin    = require "kong.plugins.base_plugin"
local responses     = require "kong.tools.responses"
local get_post_args = require "kong.tools.public".get_post_args
local table_merge   = require "kong.tools.utils".table_merge
local meta          = require "kong.meta"
local http          = require "resty.http"
local cjson         = require "cjson.safe"
local multipart     = require "multipart"

local tostring      = tostring
local concat        = table.concat
local pairs         = pairs
local lower         = string.lower
local find          = string.find
local encode_base64 = ngx.encode_base64
local get_body_data = ngx.req.get_body_data
local get_uri_args  = ngx.req.get_uri_args
local read_body     = ngx.req.read_body
local ngx_print     = ngx.print
local ngx_exit      = ngx.exit
local ngx_log       = ngx.log
local header        = ngx.header
local var           = ngx.var

local get_req_headers = ngx.req.get_headers

local SERVER        = meta._NAME .. "/" .. meta._VERSION


local function log(...)
  ngx_log(ngx.ERR, "[openwhisk] ", ...)
end


local function retrieve_parameters()

  local read_req_body = (var.request_method == "POST") or (var.request_method == "PUT")

  if read_req_body then
    read_body()
  end

  local headers = get_req_headers()
  local http_metadata = {}
  http_metadata["header"] = headers
  http_metadata["request_ip"] = var.remote_addr
  http_metadata["method"] = var.request_method

  local args = table_merge(get_uri_args(), { _http = http_metadata })

  local content_type = var.content_type

  if content_type then
    content_type = lower(content_type)

    if read_req_body and find(content_type, "multipart/form-data", nil, true) then
      return table_merge(
        args,
        multipart(get_body_data(), content_type):get_all())
    end

    if read_req_body and find(content_type, "application/json", nil, true) then
      local json, err = cjson.decode(get_body_data())
      if err then
        return nil, err
      end
      return table_merge(args, json)
    end
  end

  return table_merge(args, get_post_args())
end


local OpenWhisk = BasePlugin:extend()

OpenWhisk.PRIORITY = 1000


function OpenWhisk:new()
  OpenWhisk.super.new(self, "openwhisk")
end


function OpenWhisk:access(config)
  OpenWhisk.super.access(self)

  -- get parameters
  local body, err = retrieve_parameters()
  if err then
    return responses.send_HTTP_BAD_REQUEST(err)
  end

  -- invoke action
  local basic_auth
  if config.service_token ~= nil then
    basic_auth = "Basic " .. encode_base64(config.service_token)
  end

  local client = http.new()

  client:set_timeout(config.timeout)

  local ok, err = client:connect(config.host, config.port)
  if not ok then
    log("could not connect to Openwhisk server: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if config.https then
    local ok, err = client:ssl_handshake(false, config.host, config.https_verify)
    if not ok then
      log("could not perform SSL handshake : ", err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end

  local res, err = client:request {
    method  = "POST",
    path    = concat {          config.path,
      "/actions/",              config.action,
      "?blocking=true&result=", tostring(config.result),
      "&timeout=",              config.timeout
    },
    body    = cjson.encode(body),
    headers = {
      ["Content-Type"]  = "application/json",
      ["Authorization"] = basic_auth
    }
  }

  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- prepare response for downstream
  for k, v in pairs(res.headers) do
    header[k] = v
  end

  header.Server = SERVER
  ngx.status = res.status
  ngx_print(res:read_body())

  local ok, err = client:set_keepalive(config.keepalive)
  if not ok then
    log("could not keepalive connection: ", err)
  end

  return ngx_exit(res.status)
end


return OpenWhisk
