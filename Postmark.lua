-- Postmark: pending AH sale mail tracker for WoW Forever
local ADDON = ...
local DELAY = 3600          -- AH sale mail arrives after 1 hour
local CUT = 0.05            -- standard faction AH cut

local f = CreateFrame("Frame")
local db
local postedDeposits = {}   -- [itemName] = deposit per auction, captured at post time
local ownerSnapshot = {}    -- [itemName] = { price=, exact= } from owner list

-- ---------- helpers ----------
local function money(c)
  c = floor(c or 0)
  local g, s, cc = floor(c / 10000), floor(c / 100) % 100, c % 100
  local G = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
  local S = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
  local C = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
  local out = {}
  if g > 0 then out[#out + 1] = g .. G end
  if g > 0 or s > 0 then out[#out + 1] = s .. S end
  out[#out + 1] = cc .. C
  return table.concat(out, " ")
end

local function prune()
  local now = time()
  for i = #db.pending, 1, -1 do
    if db.pending[i].arrives <= now then table.remove(db.pending, i) end
  end
end

local function totals()
  local sum, estimate = 0, false
  for _, p in ipairs(db.pending) do
    sum = sum + p.amount
    if not p.exact then estimate = true end
  end
  return sum, estimate
end

-- Build pattern from the game's own string: "A buyer has been found for your auction of %s."
local soldPattern
do
  local s = ERR_AUCTION_SOLD_S or "A buyer has been found for your auction of %s."
  s = s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
  soldPattern = "^" .. s .. "$"
end

-- ---------- icon ----------
local btn = CreateFrame("Button", "PostmarkMinimapButton", Minimap)
btn:SetSize(24, 20)
btn:SetFrameStrata("HIGH")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetPoint("CENTER")
-- match WoW Forever's own mail icon (envelope with red wax seal)
local okAtlas = icon.SetAtlas and pcall(icon.SetAtlas, icon, "ui-hud-minimap-mail-up", true)
if okAtlas and icon:GetAtlas() then
  icon:SetSize(21, 16)
else
  icon:SetTexture("Interface\\Icons\\INV_Letter_15")
  icon:SetSize(18, 18)
end
icon:SetAlpha(0.5)
local hl = btn:CreateTexture(nil, "HIGHLIGHT")
hl:SetAllPoints(icon)
hl:SetTexture(icon:GetTexture())
if okAtlas and icon:GetAtlas() then pcall(hl.SetAtlas, hl, "ui-hud-minimap-mail-mouseover") end
hl:SetBlendMode("ADD")
local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("TOP", btn, "BOTTOM", 0, 1)
label:SetText("")
label:SetTextColor(0.8, 0.8, 0.8)
btn:Hide()

local function realMailFrame()
  local ic = MinimapCluster and MinimapCluster.IndicatorFrame
  return (ic and ic.MailFrame) or MiniMapMailFrame or (MinimapCluster and MinimapCluster.MailFrame)
end

-- copy the exact texture the game's own mail button uses
local function copyRealIcon(real)
  local tex = real.Icon or real.MailIcon or real.icon
  if not (tex and tex.GetTexture) then
    for _, r in ipairs({ real:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "Texture" and (r:GetAtlas() or r:GetTexture()) then
        tex = r; break
      end
    end
  end
  if not tex then return end
  local atlas = tex.GetAtlas and tex:GetAtlas()
  if atlas then
    icon:SetAtlas(atlas)
  else
    icon:SetTexture(tex:GetTexture())
    icon:SetTexCoord(tex:GetTexCoord())
  end
  local w, h = tex:GetSize()
  if w and w > 0 then icon:SetSize(w, h) end
end

local function anchorIcon()
  btn:ClearAllPoints()
  local real = realMailFrame()
  if real then pcall(copyRealIcon, real) end
  if real then
    -- sit exactly where WoW Forever's own mail icon shows
    btn:SetPoint("CENTER", real, "CENTER", 0, 0)
    return
  end
  -- fallback: just under the zone name above the minimap
  local zone = (MinimapCluster and MinimapCluster.ZoneTextButton) or MinimapZoneTextButton
  if zone then btn:SetPoint("TOPLEFT", zone, "BOTTOMLEFT", 4, -2)
  else btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 18) end
end

local function nextArrival()
  local soonest
  for _, p in ipairs(db.pending) do
    if not soonest or p.arrives < soonest then soonest = p.arrives end
  end
  return soonest and max(soonest - time(), 0)
end

local function timeText(sec)
  if sec >= 60 then return format("%dm", ceil(sec / 60)) end
  return format("%ds", sec)
end

local function refresh()
  if not db then return end
  prune()
  local left = nextArrival()
  label:SetText(left and timeText(left) or "")
  local realMail = HasNewMail and HasNewMail()
  if #db.pending > 0 and not realMail then btn:Show() else btn:Hide() end
end

btn:SetScript("OnEnter", function(self)
  local sum, est = totals()
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("Pending AH mail")
  GameTooltip:AddLine((est and "~" or "") .. money(sum), 1, 1, 1)
  local left = nextArrival()
  if left then GameTooltip:AddLine("Next mail in " .. timeText(left), 0.9, 0.8, 0.5) end
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)


-- ---------- AH data capture ----------
local AH = C_AuctionHouse

local function itemNameFromKeyOrLink(a)
  if a.itemLink then
    local n = a.itemLink:match("%[(.-)%]")
    if n then return n end
  end
  if a.itemKey and a.itemKey.itemID then
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(a.itemKey.itemID))
      or (GetItemInfo and GetItemInfo(a.itemKey.itemID))
  end
end

local function recordSnapshot(name, price, exact)
  ownerSnapshot[name] = { price = price, exact = exact }
  if exact then
    for _, p in ipairs(db.pending) do
      if p.item == name and not p.exact then
        p.amount = price - floor(price * CUT) + (p.deposit or 0)
        p.exact = p.deposit ~= nil
        break
      end
    end
  end
end

local function scanOwner()
  if AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo then
    local n = AH.GetNumOwnedAuctions() or 0
    for i = 1, n do
      local a = AH.GetOwnedAuctionInfo(i)
      if a then
        local name = itemNameFromKeyOrLink(a)
        if name then
          local qty = a.quantity or 1
          if a.status == 1 then
            local price = (a.bidAmount and a.bidAmount > 0 and a.bidAmount) or (a.buyoutAmount and a.buyoutAmount * qty) or 0
            recordSnapshot(name, price, true)
          else
            local price = (a.buyoutAmount and a.buyoutAmount > 0 and a.buyoutAmount * qty) or a.bidAmount or 0
            recordSnapshot(name, price, false)
          end
        end
      end
    end
    return
  end
  if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
  local n = GetNumAuctionItems("owner") or 0
  for i = 1, n do
    local name, _, count, _, _, _, _, minBid, _, buyout, bid, _, _, _, _, saleStatus =
      GetAuctionItemInfo("owner", i)
    if name then
      if saleStatus == 1 then
        local price = (bid and bid > 0) and bid or buyout or 0
        ownerSnapshot[name] = { price = price, exact = true }
        -- upgrade an already-recorded estimate for this item to exact
        for _, p in ipairs(db.pending) do
          if p.item == name and not p.exact then
            p.amount = price - floor(price * CUT) + (p.deposit or 0)
            p.exact = p.deposit ~= nil
            break
          end
        end
      else
        local price = (buyout and buyout > 0) and buyout or (bid and bid > 0 and bid) or minBid or 0
        ownerSnapshot[name] = { price = price, exact = false }
      end
    end
  end
end

-- capture deposit at post time
local function captureDeposit(runTime, stackSize, numStacks)
  if not GetAuctionSellItemInfo then return end
  local name = GetAuctionSellItemInfo()
  if not name then return end
  local dep
  if CalculateAuctionDeposit then
    local ok, d = pcall(CalculateAuctionDeposit, runTime, stackSize, numStacks)
    if ok and d then dep = d / max(numStacks or 1, 1) end
  end
  if dep then postedDeposits[name] = dep; db.deposits[name] = dep end
end
local function saveDep(name, dep)
  if name and dep then postedDeposits[name] = dep; db.deposits[name] = dep end
end
if AH and AH.PostItem then
  hooksecurefunc(AH, "PostItem", function(loc, duration, quantity, bid, buyout)
    pcall(function()
      local name = C_Item.GetItemName(loc)
      local price = (buyout and buyout > 0 and buyout) or bid
      if name and price and price > 0 then db.prices[name] = price end
      saveDep(name, AH.CalculateItemDeposit(loc, duration, quantity))
    end)
  end)
end
if AH and AH.PostCommodity then
  hooksecurefunc(AH, "PostCommodity", function(loc, duration, quantity, unitPrice)
    pcall(function()
      local name = C_Item.GetItemName(loc)
      if name and unitPrice and unitPrice > 0 then
        db.prices[name] = unitPrice * (quantity or 1)
        db.unitPrices = db.unitPrices or {}
        db.unitPrices[name] = unitPrice
      end
      local id = C_Item.GetItemID(loc)
      saveDep(name, AH.CalculateCommodityDeposit(id, duration, quantity))
    end)
  end)
end
if PostAuction then
  hooksecurefunc("PostAuction", function(_, _, runTime, stackSize, numStacks)
    captureDeposit(runTime, stackSize, numStacks)
  end)
end
if StartAuction then
  hooksecurefunc("StartAuction", function(_, _, runTime, stackSize, numStacks)
    captureDeposit(runTime, stackSize, numStacks)
  end)
end

local lastSold, lastSoldAt = nil, 0
local function onSold(item)
  if not item or item == "" then return end
  -- the same sale can arrive both as a notification and a chat line
  if item == lastSold and GetTime() - lastSoldAt < 5 then return end
  lastSold, lastSoldAt = item, GetTime()
  local snap = ownerSnapshot[item]
  if not (snap and snap.price and snap.price > 0) then
    snap = db.prices[item] and { price = db.prices[item], exact = false } or nil
  end
  local deposit = postedDeposits[item] or db.deposits[item]
  local price = snap and snap.price or 0
  local amount = price - floor(price * CUT) + (deposit or 0)
  table.insert(db.pending, {
    item = item, amount = amount, deposit = deposit,
    exact = (snap and snap.exact and deposit ~= nil) or false,
    arrives = time() + DELAY,
  })
  refresh()
end

-- ---------- events ----------
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_SYSTEM",
  "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_SHOW",
  "AUCTION_OWNED_LIST_UPDATE", "OWNED_AUCTIONS_UPDATED",
  "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "AUCTION_HOUSE_SHOW_NOTIFICATION" }) do
  pcall(f.RegisterEvent, f, ev)
end

f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    PostmarkDB = PostmarkDB or {}
    db = PostmarkDB
    db.pending = db.pending or {}
    db.deposits = db.deposits or {}
    db.prices = db.prices or {}
    print("|cff88ccffPostmark|r loaded. Type /postmark or /pm (test: /postmark test).")
  elseif not db then return
  elseif event == "PLAYER_ENTERING_WORLD" then
    anchorIcon(); refresh()
  elseif event == "CHAT_MSG_SYSTEM" then
    local item = arg1 and (arg1:match(soldPattern)
      or arg1:match("[Bb]uyer.-auction of%s+(.-)%.?$")
      or arg1:match("[Aa]uction of%s+(.-)%s+has sold%.?$")
      or arg1:match("[Yy]our auction of%s+(.-)%s+sold%.?$"))
    if item then item = item:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1") end
    if item then onSold(item) end
  elseif event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" or event == "AUCTION_HOUSE_SHOW_NOTIFICATION" then
    local soldEnum = Enum and Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold
    if soldEnum and arg1 == soldEnum and arg2 then
      local item = tostring(arg2):match("%[(.-)%]") or tostring(arg2)
      onSold(item)
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    if AH and AH.QueryOwnedAuctions then pcall(AH.QueryOwnedAuctions, {})
    elseif GetOwnerAuctionItems then pcall(GetOwnerAuctionItems) end
  elseif event == "AUCTION_OWNED_LIST_UPDATE" or event == "OWNED_AUCTIONS_UPDATED" then
    scanOwner()
    for name, s in pairs(ownerSnapshot) do
      if s.price and s.price > 0 then db.prices[name] = s.price end
    end
  else
    refresh()
  end
end)

C_Timer.NewTicker(1, refresh)

-- ---------- slash ----------
SLASH_POSTMARK1 = "/pm"
SLASH_POSTMARK2 = "/postmark"
SlashCmdList.POSTMARK = function(msg)
  if not db then return end
  msg = (msg or ""):lower()
  if msg == "test" then
    table.insert(db.pending, { item = "Test Item", amount = 12345, exact = true, arrives = time() + 120 })
    anchorIcon(); refresh()
    print("|cff88ccffPostmark|r: test sale added (gone in 2 min). Real mail waiting hides the icon.")
    return
  end
  if msg == "debug" then
    local real = realMailFrame()
    print("|cff88ccffPostmark|r debug: mail frame =", real and (real:GetName() or "unnamed") or "NOT FOUND")
    if real then
      local function dump(fr, depth)
        for _, r in ipairs({ fr:GetRegions() }) do
          if r:GetObjectType() == "Texture" then
            print(depth .. "tex", r:GetDebugName(), "atlas:", tostring(r:GetAtlas()), "file:", tostring(r:GetTexture()), "size:", r:GetSize())
          end
        end
        for _, c in ipairs({ fr:GetChildren() }) do
          print(depth .. "child", c:GetDebugName())
          if #depth < 4 then dump(c, depth .. "  ") end
        end
      end
      dump(real, "  ")
    end
    print("  ghost icon atlas:", tostring(icon:GetAtlas()), "file:", tostring(icon:GetTexture()))
    return
  end
  if msg == "clear" then
    wipe(db.pending); refresh()
    print("|cff88ccffPostmark|r: cleared pending sales.")
    return
  end
  prune()
  local sum, est = totals()
  print(format("|cff88ccffPostmark|r: %d pending sale(s), %s%s incoming.", #db.pending, est and "~" or "", money(sum)))
  local now = time()
  for _, p in ipairs(db.pending) do
    print(format("  %s: %s%s (%d min)", p.item, p.exact and "" or "~", money(p.amount), ceil((p.arrives - now) / 60)))
  end
  print("  /pm clear - reset the list")
end
