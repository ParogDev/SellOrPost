-- The verdict: is this bag item junk (sell it at a vendor) or not? Pure functions, no client calls, so busted can
-- test every branch. Core.lua gathers the inputs from the client and TSM.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

-- TSM custom price string evaluated per item. It is the same test every Auctioning operation's post cap runs
-- (`ifgte(first(post, 0.001), 1, 1000, 0)`): under 1 copper means "Posting disabled.", which in this setup means
-- vendor it. `post` is a custom price source defined in TSM itself. The answer is 1 (vendor) or 2 (posts), never
-- 0: TSM_API.GetCustomPriceValue turns a 0 into nil, which would read as a failure. nil therefore means the string
-- did not evaluate (no `post` source).
Logic.POST_STRING = "ifgte(first(post, 0.001), 1, 2, 1)"
Logic.GATE_VENDOR = 1
Logic.GATE_POSTS = 2

-- Group rules: TSM group path (subgroups joined by "`") -> true (may be marked) or false (never marked). The
-- longest matching prefix wins, so a subgroup can undo its parent. Groups not listed may be marked.
-- These are the groups this setup holds instead of posting or vendoring.
Logic.DEFAULT_RULES = {
	["Keep (never post)"] = false,
	["Materials`Vendor-bought"] = false,
	["Materials`Leather"] = false,
	["Materials`Leather`Outgrown tiers"] = true,
	["Materials`Leather`Pristine Scale"] = false,
}

-- The rule for one group path, or nil when no rule covers it.
function Logic.ruleFor(path, rules)
	local best, bestLen = nil, -1
	for prefix, mark in pairs(rules) do
		local n = #prefix
		if n > bestLen and (path == prefix or path:sub(1, n + 1) == prefix .. "`") then
			best, bestLen = mark, n
		end
	end
	return best
end

-- item: { quality, sellPrice, lookupError, groupPath, post (GATE_*), postError }
-- Returns junk (boolean) and a reason (string). Reasons that start with "broken:" are failures to report; the
-- rest are ordinary verdicts.
function Logic.verdict(item, rules)
	if not item.sellPrice or item.sellPrice <= 0 then
		return false, "no vendor price"
	end
	if item.lookupError then
		return false, "broken: " .. item.lookupError -- group unknown: even a grey may be held
	end
	if item.groupPath and Logic.ruleFor(item.groupPath, rules) == false then
		return false, "held group" -- wins over "poor quality": a held grey stays
	end
	if item.quality == 0 then
		return true, "poor quality"
	end
	if not item.groupPath then
		return false, "not in a TSM group"
	end
	if item.post == Logic.GATE_VENDOR then
		return true, "post rule says vendor"
	elseif item.post == Logic.GATE_POSTS then
		return false, "posts"
	end
	return false, "broken: " .. (item.postError or ("post price string gave " .. tostring(item.post)))
end

-- Merges saved overrides (path -> boolean) over the defaults; anything else in the saved table is ignored.
function Logic.mergeRules(defaults, saved)
	local out = {}
	for k, v in pairs(defaults) do
		out[k] = v
	end
	if type(saved) == "table" then
		for k, v in pairs(saved) do
			if type(k) == "string" and type(v) == "boolean" then
				out[k] = v
			end
		end
	end
	return out
end

function Logic.money(c)
	c = math.floor(c or 0)
	local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	if g > 0 then
		return string.format("%dg %ds %dc", g, s, cp)
	elseif s > 0 then
		return string.format("%ds %dc", s, cp)
	end
	return string.format("%dc", cp)
end

return Logic
