return {
  fields = {
    timeout       = { type = "number",  default  = 60000 },
    keepalive     = { type = "number",  default  = 60000 },
    service_token = { type = "string"                    },
    host          = { type = "string",  required = true  },
    port          = { type = "number",  default  = 443   },
    path          = { type = "string",  required = true  },
    type          = { type = "string",  required = true  },
    entity        = { type = "string",  required = true  },
    https         = { type = "boolean", default  = true  },
    https_verify  = { type = "boolean", default  = false },
    result        = { type = "boolean", default  = true  },
  },
  self_check = function (schema, config, dao, is_updating)
    local is_config_valid = true
    local allowed_types = "actions, triggers"
    if config.type and string.find( allowed_types , config.type ) then
      is_config_valid = true
    else
      is_config_valid = false
    end
    -- body
    return is_config_valid
  end
}
