local mock = require("tests.wow_mock")

describe("Logic", function()
	local L
	before_each(function()
		mock.install()
		L = mock.loadAddon(".").Logic
	end)

	describe("ruleFor", function()
		local rules = { ["A"] = false, ["A`B"] = true, ["C`D"] = false }

		it("returns nil when nothing covers the path", function()
			assert.is_nil(L.ruleFor("Z", rules))
			assert.is_nil(L.ruleFor("C", rules))
		end)

		it("matches the group and its subgroups", function()
			assert.is_false(L.ruleFor("A", rules))
			assert.is_false(L.ruleFor("A`X`Y", rules))
		end)

		it("lets the longest prefix win", function()
			assert.is_true(L.ruleFor("A`B", rules))
			assert.is_true(L.ruleFor("A`B`C", rules))
		end)

		it("does not match a name that only starts the same", function()
			assert.is_nil(L.ruleFor("AB", rules))
			assert.is_nil(L.ruleFor("C`DE", rules))
		end)
	end)

	describe("verdict", function()
		local rules
		before_each(function()
			rules = L.mergeRules(L.DEFAULT_RULES, nil)
		end)

		local function v(item)
			return L.verdict(item, rules)
		end

		it("never marks an item the vendor will not buy", function()
			assert.same({ false, "no vendor price" }, { v({ quality = 0, sellPrice = 0 }) })
			assert.same({ false, "no vendor price" }, { v({ quality = 2, groupPath = "BoE gear", post = 0 }) })
		end)

		it("marks grey items with a vendor price, grouped or not", function()
			assert.same({ true, "poor quality" }, { v({ quality = 0, sellPrice = 5 }) })
		end)

		it("keeps a grey item in a held group", function()
			assert.same({ false, "held group" }, { v({ quality = 0, sellPrice = 5, groupPath = "Keep (never post)" }) })
		end)

		it("leaves ungrouped items alone", function()
			assert.same({ false, "not in a TSM group" }, { v({ quality = 1, sellPrice = 5, post = 0 }) })
		end)

		it("marks an item the post rule refuses", function()
			local item = { quality = 1, sellPrice = 5, groupPath = "Consumables and other goods", post = 0.001 }
			assert.same({ true, "post rule says vendor" }, { v(item) })
		end)

		it("does not mark an item that posts", function()
			local item = { quality = 2, sellPrice = 500, groupPath = "BoE gear`Greens 20-39", post = 12000 }
			assert.same({ false, "posts" }, { v(item) })
		end)

		it("holds the Keep, Vendor-bought and current leather groups", function()
			for _, path in ipairs({ "Keep (never post)", "Materials`Vendor-bought", "Materials`Leather" }) do
				assert.same({ false, "held group" }, { v({ quality = 1, sellPrice = 5, groupPath = path, post = 0 }) })
			end
		end)

		it("marks outgrown leather the parent group holds", function()
			local item = { quality = 1, sellPrice = 5, groupPath = "Materials`Leather`Outgrown tiers", post = 0 }
			assert.is_true((v(item)))
		end)

		it("reports a missing post value as broken, not as a sale", function()
			local junk, reason = v({ quality = 1, sellPrice = 5, groupPath = "Bags", postError = "no `post` source" })
			assert.is_false(junk)
			assert.equal("broken: no `post` source", reason)
		end)
	end)

	describe("mergeRules", function()
		it("lets saved booleans override and ignores anything else", function()
			local r = L.mergeRules({ A = false, B = true }, { A = true, C = false, D = "x", [1] = true })
			assert.same({ A = true, B = true, C = false }, r)
		end)
	end)

	it("formats money", function()
		assert.equal("3c", L.money(3))
		assert.equal("1s 5c", L.money(105))
		assert.equal("2g 0s 7c", L.money(20007))
	end)
end)
