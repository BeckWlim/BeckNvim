local Cache = require("src.cache")

-- Keep frequently requested pages close to the reader.
local pages = Cache.new(120)

local function load_page(path)
    local cached = pages:get(path)
    if cached then
        return cached
    end

    local page = { path = path, title = "Welcome to BeckNvim" }
    pages:put(path, page)
    return page
end

local page = load_page("/docs")
print(page.title)
