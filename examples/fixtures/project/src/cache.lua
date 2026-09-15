local Cache = {}
Cache.__index = Cache

function Cache.new(ttl)
    return setmetatable({
        entries = {},
        ttl = ttl or 60,
        hits = 0,
        misses = 0,
    }, Cache)
end

function Cache:get(key)
    local entry = self.entries[key]

    -- Expired values should be fetched again.
    if entry and entry.expires > os.time() then
        self.hits = self.hits + 1
        return entry.value
    end

    self.entries[key] = nil
    self.misses = self.misses + 1
    return nil
end

function Cache:put(key, value)
    self.entries[key] = {
        value = value,
        expires = os.time() + self.ttl,
    }
end

return Cache
