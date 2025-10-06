ESX = exports['es_extended']:getSharedObject()

-- ============== Helpers ==============
local SOCIETY_ACCOUNT = 'society_concess'
local DEFAULT_SOCIETY = 'society_concess'
local ALLOWED_PAYS    = { bank = true, money = true }

local function notify(src, data)
  -- data: {title, description, type, id}
  TriggerClientEvent('ox_lib:notify', src, {
    id = data.id,
    title = data.title or 'Info',
    description = data.description or '',
    type = data.type or 'inform',
    position = data.position or 'center-left',
    duration = data.duration or 5000
  })
end

local function addHistory(src, typ, cost, gain, vehicle)
  local name = GetPlayerName(src) or ('src:'..src)
  local dt = os.date('*t')
  local date = string.format('%02d/%02d/%04d à %02dh%02d', dt.day, dt.month, dt.year, dt.hour, dt.min)
  MySQL.insert.await(
    'INSERT INTO historique_concessionnaire (type, gain, cost, vehicle, identifier, date) VALUES (?, ?, ?, ?, ?, ?)',
    { typ, tostring(gain or '/'), tostring(cost or '/'), tostring(vehicle or '/'), name, date }
  )
end

local function addSocietyMoney(amount, account)
  account = account or SOCIETY_ACCOUNT
  local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
  if not row then return false end
  local new = (tonumber(row.money) or 0) + (tonumber(amount) or 0)
  MySQL.update.await('UPDATE addon_account_data SET money = ? WHERE account_name = ?', { new, account })
  return true
end

lib.callback.register('ledjo:count_staff_online', function(source, shopId)
    local count = 0
    local jobs = {}
    local s = Config.Shops and Config.Shops[shopId]
    if s then
        if s.jobs then for j,_ in pairs(s.jobs) do jobs[j] = true end end
        if s.job then jobs[s.job] = true end
    end
    for _, id in ipairs(ESX.GetPlayers()) do
        local xP = ESX.GetPlayerFromId(id)
        local jname = (xP.getJob and xP.getJob().name) or (xP.job and xP.job.name)
        if jname and jobs[jname] then count = count + 1 end
    end
    return count
end)


local function removeSocietyMoney(amount, account)
  account = account or SOCIETY_ACCOUNT
  local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
  if not row then return false end
  local cur = tonumber(row.money) or 0
  if cur < amount then return false end
  MySQL.update.await('UPDATE addon_account_data SET money = ? WHERE account_name = ?', { cur - amount, account })
  return true
end

local function getVehRow(modelOrName)
  return MySQL.single.await(
    'SELECT name, model, price, category, stock, image FROM vehicles WHERE model = ? OR name = ? LIMIT 1',
    { modelOrName, modelOrName }
  )
end

-- ============== Annonces =================
RegisterNetEvent('ledjo_concess:AnnonceOuverture', function()
  for _, id in ipairs(ESX.GetPlayers()) do
    notify(id, { id='AO', title='La Concession', description="La concession vient d'ouvrir ses portes !", type='success', position='top-center', duration=6000 })
  end
end)

RegisterNetEvent('ledjo_concess:AnnonceFermeture', function()
  for _, id in ipairs(ESX.GetPlayers()) do
    notify(id, { id='AF', title='La Concession', description="La concession ferme. Mode automatique activé.", type='inform', position='top-center', duration=6000 })
  end
end)

RegisterNetEvent('ledjo_concess:AnnoncePerso', function(content)
  for _, id in ipairs(ESX.GetPlayers()) do
    notify(id, { id='AR', title='Concession', description=tostring(content or ''), type='inform', position='top-center', duration=6000 })
  end
end)

-- ============== Catalogue / Données ==============
lib.callback.register('ledjo:concess_liste_cat', function()
  return MySQL.query.await('SELECT name, label, image FROM vehicle_categories ORDER BY label')
end)

lib.callback.register('ledjo:concess_liste_veh_from_cat', function(_, cat)
  return MySQL.query.await(
    'SELECT name, model, price, category, stock, image FROM vehicles WHERE category = ? ORDER BY price',
    { cat }
  )
end)

lib.callback.register('ledjo:concess_liste_veh', function()
  return MySQL.query.await('SELECT name, model, price, category, stock, image FROM vehicles')
end)

-- ============== Mode auto ==============
lib.callback.register('ledjo:concess_auto_verif', function()
  return MySQL.query.await('SELECT statut FROM automatisation WHERE society_concess = ?', { 'concess' })
end)

RegisterNetEvent('ledjo:concess_update_automatisation', function(statut)
  MySQL.update.await('UPDATE automatisation SET statut = ? WHERE society_concess = ?', { tostring(statut), 'concess' })
  notify(source, { id='auto', title='Changement de mode', description=('Mode défini sur : %s'):format(tostring(statut)), type='success', position='top-center' })
end)

-- ============== Vérifications argent ==============
lib.callback.register('ledjo:concess_verif_money', function(source, price, pay)
  local xP = ESX.GetPlayerFromId(source)
  if not xP or not ALLOWED_PAYS[pay or ''] then return false end
  return (xP.getAccount(pay).money or 0) >= (tonumber(price) or 0)
end)

lib.callback.register('ledjo:concess_verif_money_vendeur', function(_, price, pay, targetId)
  local tgt = ESX.GetPlayerFromId(tonumber(targetId) or -1)
  if not tgt or not ALLOWED_PAYS[pay or ''] then return false end
  return (tgt.getAccount(pay).money or 0) >= (tonumber(price) or 0)
end)

lib.callback.register('ledjo:concess_verif_money_entreprise', function(_, price, account)
  local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
  return row and (tonumber(row.money) or 0) >= (tonumber(price) or 0) or false
end)

-- ============== Achats ==============
RegisterNetEvent('ledjo:concess_buy_car', function(name, _clientPrice, props, plate, _stockClient, _rgb, pay)
  local src = source
  if not props or not props.model then return end
  if not ALLOWED_PAYS[pay or ''] then return end

  local veh = getVehRow(props.model) or getVehRow(name)
  if not veh then return notify(src, { title='Achat', description='Véhicule introuvable', type='error' }) end
  if (veh.stock or 0) <= 0 then return notify(src, { title='Achat', description='Rupture de stock', type='error' }) end

  local price = tonumber(veh.price) or 0
  local xP = ESX.GetPlayerFromId(src); if not xP then return end
  if xP.getAccount(pay).money < price then return notify(src, { title='Achat', description='Fonds insuffisants', type='error' }) end

  xP.removeAccountMoney(pay, price)
  MySQL.update.await('UPDATE vehicles SET stock = stock - 1 WHERE model = ? OR name = ?', { veh.model, veh.name })
  MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?)', { xP.identifier, plate, json.encode(props) })
  addSocietyMoney(price)
  notify(src, { title='Achat', description=('Vous avez acheté : %s'):format(veh.name), type='success' })
  addHistory(src, 'Vente', '/', price, veh.name)
end)

RegisterNetEvent('ledjo:concess_buy_car_vendeur', function(name, _clientPrice, props, plate, _stockClient, _rgb, pay, targetId)
  local sellerSrc = source
  local seller = ESX.GetPlayerFromId(sellerSrc)
  if not seller or seller.job.name ~= 'concess' then
    return notify(sellerSrc, { title='Vente', description='Accès réservé au personnel', type='error' })
  end
  if not props or not props.model or not ALLOWED_PAYS[pay or ''] then return end

  local veh = getVehRow(props.model) or getVehRow(name)
  if not veh then return notify(sellerSrc, { title='Vente', description='Véhicule introuvable', type='error' }) end
  if (veh.stock or 0) <= 0 then return notify(sellerSrc, { title='Vente', description='Rupture de stock', type='error' }) end

  local buyer = ESX.GetPlayerFromId(tonumber(targetId) or -1)
  if not buyer then return notify(sellerSrc, { title='Vente', description='Client introuvable', type='error' }) end

  local price = tonumber(veh.price) or 0
  if buyer.getAccount(pay).money < price then
    return notify(sellerSrc, { title='Vente', description="Le client n'a pas assez d'argent", type='error' })
  end

  buyer.removeAccountMoney(pay, price)
  MySQL.update.await('UPDATE vehicles SET stock = stock - 1 WHERE model = ? OR name = ?', { veh.model, veh.name })
  MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?)', { buyer.identifier, plate, json.encode(props) })
  addSocietyMoney(price)

  notify(buyer.source,  { title='Achat', description=('Vous avez acheté : %s'):format(veh.name), type='success' })
  notify(sellerSrc,     { title='Vente', description=('Vendu %s pour %s$'):format(veh.name, price), type='success' })
  addHistory(sellerSrc, 'Vente (vendeur)', '/', price, veh.name)
end)

RegisterNetEvent('ledjo:concess_buy_car_entreprise', function(name, _clientPrice, props, plate, _stockClient, label, _rgb, account)
  local src = source
  if not props or not props.model then return end

  local veh = getVehRow(props.model) or getVehRow(name)
  if not veh then return notify(src, { title='Vente', description='Véhicule introuvable', type='error' }) end
  if (veh.stock or 0) <= 0 then return notify(src, { title='Vente', description='Rupture de stock', type='error' }) end

  local price = tonumber(veh.price) or 0
  local acc = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
  if not acc or (tonumber(acc.money) or 0) < price then
    return notify(src, { title='Vente', description="Entreprise sans fonds", type='error' })
  end

  removeSocietyMoney(price, account)
  MySQL.update.await('UPDATE vehicles SET stock = stock - 1 WHERE model = ? OR name = ?', { veh.model, veh.name })
  MySQL.insert.await('INSERT INTO society_concess_vehicles (society_concess, plate, vehicle, label) VALUES (?, ?, ?, ?)',
    { account, plate, json.encode(props), label or veh.name })
  if account ~= SOCIETY_ACCOUNT then addSocietyMoney(price) end

  notify(src, { title='Vente', description=('Vendu %s à %s'):format(veh.name, account), type='success' })
  addHistory(src, 'Vente (entreprise)', '/', price, veh.name)
end)

ESX.RegisterServerCallback('ledjo:concess_isPlateTaken', function(_, cb, plate)
  local r = MySQL.scalar.await('SELECT plate FROM owned_vehicles WHERE plate = ?', { plate })
  cb(r ~= nil)
end)

-- ============== Historique ==============
lib.callback.register('ledjo:concess_historique', function()
  return MySQL.query.await('SELECT * FROM historique_concessionnaire ORDER BY id DESC')
end)

RegisterNetEvent('ledjo:concess_delete_historique', function(id)
  MySQL.update.await('DELETE FROM historique_concessionnaire WHERE id = ?', { tonumber(id) })
  notify(source, { title='Historique', description='Ligne supprimée.', type='success' })
end)

-- ============== Employés / Salaires ==============
RegisterNetEvent('ledjo:concess_change_salaire', function(salary, grade)
  MySQL.update.await('UPDATE job_grades SET salary = ? WHERE job_name = ? AND grade = ?', { tonumber(salary) or 0, 'concess', tonumber(grade) or 0 })
  notify(source, { title='Salaires', description=('Salaire grade %s -> %s$'):format(grade, salary), type='success' })
end)

RegisterNetEvent('ledjo:concess_recruit', function(targetId)
  local tgt = ESX.GetPlayerFromId(targetId); if not tgt then return end
  MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { 'concess', 1, tgt.identifier })
  notify(source, { title='Recrutement', description=('Vous avez recruté %s'):format(GetPlayerName(targetId)), type='success' })
end)

lib.callback.register('ledjo:concess_employed', function()
  return MySQL.query.await('SELECT identifier, firstname, lastname, sex, dateofbirth, job_grade FROM users WHERE job = ?', { 'concess' })
end)

lib.callback.register('ledjo:concess_salaire_table', function()
  return MySQL.query.await('SELECT grade, label, salary FROM job_grades WHERE job_name = ? ORDER BY grade', { 'concess' })
end)

RegisterNetEvent('ledjo:concess_modify_grade', function(newGrade, identifier)
  MySQL.update.await('UPDATE users SET job_grade = ? WHERE identifier = ?', { tonumber(newGrade) or 0, identifier })
  notify(source, { title='Employés', description='Grade modifié.', type='success' })
end)

RegisterNetEvent('ledjo:concess_delete_grade', function(identifier)
  MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { 'unemployed', 0, identifier })
  notify(source, { title='Employés', description='Employé licencié.', type='success' })
end)

-- ============== Compte société ==============
lib.callback.register('ledjo:concess_money', function()
  return MySQL.query.await('SELECT account_name, money FROM addon_account_data WHERE account_name = ?', { SOCIETY_ACCOUNT })
end)

RegisterNetEvent('ledjo:add_money_society_concess', function(_, add)
  local xP = ESX.GetPlayerFromId(source); if not xP then return end
  add = tonumber(add) or 0
  if xP.getAccount('money').money < add then
    return notify(source, { title='Compte', description="Montant insuffisant.", type='error' })
  end
  xP.removeAccountMoney('money', add)
  addSocietyMoney(add)
  notify(source, { title='Compte', description=('Dépôt de %s$ effectué.'):format(add), type='success' })
end)

RegisterNetEvent('ledjo:remove_money_society_concess', function(_, rm)
  rm = tonumber(rm) or 0
  if not removeSocietyMoney(rm) then
    return notify(source, { title='Compte', description="Solde insuffisant.", type='error' })
  end
  local xP = ESX.GetPlayerFromId(source); if xP then xP.addAccountMoney('money', rm) end
  notify(source, { title='Compte', description=('Retrait de %s$ effectué.'):format(rm), type='success' })
end)

-- ============== Garage société (option) ==============
lib.callback.register('ledjo:concess_garage', function()
  return MySQL.query.await('SELECT * FROM society_concess_vehicles WHERE society_concess = ? AND stored = 1', { SOCIETY_ACCOUNT })
end)

lib.callback.register('ledjo:concess_GetVehiclesociety_concess', function()
  return MySQL.query.await('SELECT * FROM society_concess_vehicles WHERE society_concess = ?', { SOCIETY_ACCOUNT })
end)

lib.callback.register('ledjo:concess_Vehiculesociety_concess', function(_, plate)
  local r = MySQL.single.await('SELECT plate FROM society_concess_vehicles WHERE society_concess = ? AND plate = ?', { SOCIETY_ACCOUNT, plate })
  return r ~= nil
end)

RegisterNetEvent('ledjo:concess_SaveStatsEntrer', function(plate, stored, props)
  MySQL.update.await('UPDATE society_concess_vehicles SET stored = ?, vehicle = ? WHERE plate = ?', { tonumber(stored) or 1, json.encode(props), plate })
end)

RegisterNetEvent('ledjo:concess_SaveSortie', function(plate)
  MySQL.update.await('UPDATE society_concess_vehicles SET stored = 0 WHERE plate = ?', { plate })
end)

RegisterNetEvent('ledjo:concess_CautionVehiclesociety_concess', function(plate)
  MySQL.update.await('UPDATE society_concess_vehicles SET stored = 1 WHERE plate = ?', { plate })
end)

RegisterNetEvent('ledjo:concess_SellVehiclesociety_concess', function(plate, displayModel, societyAcc)
  local src = source
  local vehRow = MySQL.single.await('SELECT price FROM vehicles WHERE model = ? OR name = ? LIMIT 1', { displayModel, displayModel })
  if not vehRow then return end
  local income = math.floor((tonumber(vehRow.price) or 0) * 0.75)
  MySQL.update.await('DELETE FROM society_concess_vehicles WHERE plate = ? AND society_concess = ?', { plate, societyAcc })
  addSocietyMoney(income)
  notify(src, { title='Revente', description=('Revente effectuée : +%s$'):format(income), type='success' })
end)

-- ============== Clés (ox_inventory) ==============
local function AddCarkey(src, plate, model)
  exports.ox_inventory:AddItem(src, Config.Keyitem, 1, { plate = plate, model = model })
end
exports('AddCarkey', AddCarkey)

lib.callback.register('carkeys:callback:getPlayerVehicles', function(source)
  local xP = ESX.GetPlayerFromId(source)
  local out, rows = {}, MySQL.query.await('SELECT vehicle FROM owned_vehicles WHERE owner = ?', { xP.identifier }) or {}
  for _, r in ipairs(rows) do
    local v = json.decode(r.vehicle)
    out[#out+1] = { plate = v.plate, model = v.model }
  end
  return out
end)


-- ====== Plaques uniques "ABC 1234" ======
math.randomseed(GetGameTimer() + os.time())

local PlateReservations = {}           -- [plate] = expireAt (GetGameTimer ms)
local RESERVE_TTL_MS    = 120000       -- 2 minutes

local function randFrom(s)
    local i = math.random(#s)
    return s:sub(i, i)
end

local function makePlateABC1234()
    local L = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local letters = randFrom(L) .. randFrom(L) .. randFrom(L)
    local numbers = string.format('%04d', math.random(0, 9999))
    return (letters .. ' ' .. numbers)
end

local function plateExistsDB(plate)
    plate = tostring(plate or ''):gsub('%s+$','')  -- trim fin
    if plate == '' then return true end

    -- oxmysql (global MySQL) recommandé
    if MySQL and MySQL.scalar then
        local row = MySQL.scalar.await('SELECT 1 FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        return row ~= nil
    end

    -- exports oxmysql (certaines versions)
    if exports.oxmysql and exports.oxmysql.scalar then
        local row = exports.oxmysql:scalarSync('SELECT 1 FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        return row ~= nil
    end

    -- mysql-async (fallback)
    if MySQL and MySQL.Sync and MySQL.Sync.fetchScalar then
        local row = MySQL.Sync.fetchScalar('SELECT 1 FROM owned_vehicles WHERE plate = @plate LIMIT 1', { ['@plate'] = plate })
        return row ~= nil
    end

    -- si aucune DB détectée, considère "existe" pour ne pas casser
    print('[concess] Aucune librairie SQL détectée pour vérifier la plaque.')
    return true
end

-- Nettoyage périodique des réservations expirées
CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for p, exp in pairs(PlateReservations) do
            if exp <= now then PlateReservations[p] = nil end
        end
    end
end)

-- Alloue une plaque unique et la "réserve" quelques minutes
lib.callback.register('concess:plate:alloc', function(source)
    for _ = 1, 80 do                -- 80 tentatives max
        local plate = makePlateABC1234()
        if not PlateReservations[plate] and not plateExistsDB(plate) then
            PlateReservations[plate] = GetGameTimer() + RESERVE_TTL_MS
            return plate
        end
    end
    return false
end)

-- (Optionnel) Libérer explicitement une plaque si tu veux
RegisterNetEvent('concess:plate:confirm', function(plate)
    -- appelle ceci après avoir inséré le véhicule en DB si tu veux prolonger,
    -- sinon laisse expirer; ici on supprime la réservation
    if plate then PlateReservations[plate] = nil end
end)

-- ========= REPO / Récupération =========

-- Retourne un véhicule aléatoire (model, name, price)
lib.callback.register('concess:repo:randomVehicle', function(source)
    local row = MySQL.query.await('SELECT model, name, price FROM vehicles ORDER BY RAND() LIMIT 1', {})
    return (row and row[1]) or nil
end)

-- Démarrer une mission : le serveur choisit et renvoie au client
RegisterNetEvent('concess:repo:request', function()
    local src = source
    local veh = MySQL.query.await('SELECT model, name, price FROM vehicles ORDER BY RAND() LIMIT 1', {})
    if not veh or not veh[1] then
        TriggerClientEvent('ox_lib:notify', src, {title='Récupération', type='error', description='Aucun véhicule disponible.'})
        return
    end
    TriggerClientEvent('concess:repo:startClient', src, veh[1])
end)

-- Fin de mission (arrivé au dépôt)
RegisterNetEvent('concess:repo:complete', function(model, shopIdOrSociety)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local row = MySQL.query.await('SELECT name, price FROM vehicles WHERE model = ?', {model})
    if not (row and row[1]) then
        TriggerClientEvent('ox_lib:notify', src, {title='Réassort', type='error', description='Modèle introuvable en base.'})
        return
    end

    local price = tonumber(row[1].price) or 0
    local cost  = math.floor(price * 0.70 + 0.5) -- 70% du prix

    -- Résolution du compte société
    local society = DEFAULT_SOCIETY
    if type(shopIdOrSociety) == 'string' and shopIdOrSociety:find('^society_') then
        society = shopIdOrSociety
    elseif type(shopIdOrSociety) == 'string' and Config and Config.Shops
        and Config.Shops[shopIdOrSociety] and Config.Shops[shopIdOrSociety].society then
        society = Config.Shops[shopIdOrSociety].society
    end

    -- Débit du compte société + MAJ stock
    TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
        if not account then
            TriggerClientEvent('ox_lib:notify', src, {title='Réassort', type='error', description='Compte entreprise introuvable.'})
            return
        end

        if (account.money or 0) < cost then
            TriggerClientEvent('ox_lib:notify', src, {title='Réassort', type='error', description=('Fonds insuffisants (%s$ requis).'):format(cost)})
            return
        end

        account.removeMoney(cost)
        MySQL.update.await('UPDATE vehicles SET stock = stock + 1 WHERE model = ?', {model})

        local name = row[1].name or model
        local date = os.date("%d/%m/%Y à %Hh%M")

        MySQL.insert.await(
            'INSERT INTO historique_concessionnaire (type, gain, cost, vehicle, identifier, date) VALUES (?, ?, ?, ?, ?, ?)',
            {'Réassort', 0, cost, name, GetPlayerName(src), date}
        )

        TriggerClientEvent('ox_lib:notify', src, {
            title='Réassort',
            type='success',
            description=('Véhicule ajouté: %s (+1 stock) | Coût: %s$ (entreprise)'):format(name, cost)
        })
    end)
end)

-- ====== VENTE "PAPIER" ======
local PendingBills = {}

local function newToken()
  return ('B%06d'):format(math.random(0,999999))
end

-- Demande d'émission (vendeur -> serveur)
RegisterNetEvent('concess:sell:requestPay', function(targetId, payload)
  local seller = source
  if not targetId or not payload or not payload.model then return end
  local tkn = newToken()
  PendingBills[tkn] = {
    sellerId = seller,
    targetId = tonumber(targetId),
    model    = payload.model,
    name     = payload.name or payload.model,
    price    = tonumber(payload.price or 0),
    pay      = 'bank',
    shopId   = payload.shopId
  }
  TriggerClientEvent('concess:sell:bill', targetId, tkn, seller, PendingBills[tkn])
end)

-- Réponse du client (acheteur -> serveur)
RegisterNetEvent('concess:sell:answer', function(token, accepted, pay)
  local buyer = source
  local bill = PendingBills[token]
  if not bill or bill.targetId ~= buyer then return end
  if not accepted then
    TriggerClientEvent('concess:sell:denied', bill.sellerId, 'Le client a refusé.')
    PendingBills[token] = nil
    return
  end
  bill.pay = (pay == 'money') and 'money' or 'bank'
  -- informer le vendeur : il pourra livrer (l’UI déclenchera ui:buyAsDealer avec targetId forcé)
  TriggerClientEvent('concess:sell:paid', bill.sellerId, {
    targetId = bill.targetId, model = bill.model, name = bill.name, price = bill.price, pay = bill.pay, shopId = bill.shopId
  })
  PendingBills[token] = nil
end)




-- ======= STOCK / LOGISTIQUE =======
lib.callback.register('concess:stock:list', function()
  return MySQL.query.await('SELECT name, model, price, category, stock, image FROM vehicles ORDER BY category, price')
end)

RegisterNetEvent('concess:stock:order', function(model, qty, shopId)
  local src = source
  qty = tonumber(qty) or 1
  if qty <= 0 then return end

  local shop = (Config.Shops or {})[shopId or ''] or {}
  local society = shop.society or 'society_concess'
  local mult = (shop.comptoir and shop.comptoir.restockMultiplicateur) or 0.3

  local v = MySQL.single.await('SELECT name, price, stock FROM vehicles WHERE model = ? OR name = ? LIMIT 1', { model, model })
  if not v then
    notify(src, { title='Réassort', description='Modèle introuvable', type='error' })
    return
  end

  local unit = tonumber(v.price) or 0
  local cost = math.floor(unit * mult) * qty  -- coût d’achat grossiste

  local ok = removeSocietyMoney(cost, society)
  if not ok then
    notify(src, { title='Réassort', description='Solde société insuffisant', type='error' })
    return
  end

  MySQL.update.await('UPDATE vehicles SET stock = stock + ? WHERE model = ? OR name = ?', { qty, model, model })
  notify(src, { title='Réception', description=('Commande validée: +%d %s (-%s$)').format(qty, v.name or model, cost), type='success' })
  addHistory(src, 'Réassort', cost, '/', v.name or model)
end)

-- Restock : shopId, model, qty, mult
RegisterNetEvent('ledjo:concess_restock', function(shopId, model, qty, mult)
  local src = source
  qty  = tonumber(qty) or 1
  if qty < 1 then qty = 1 end

  local s = Config.Shops and Config.Shops[shopId] or nil
  local account = (s and s.society) or 'society_concess'
  mult = tonumber(mult) or (s and s.comptoir and s.comptoir.restockMultiplicateur) or 0.3

  local veh = getVehRow(model)
  if not veh then
    return notify(src, { title='Réappro', description='Modèle introuvable.', type='error' })
  end

  local unit = tonumber(veh.price) or 0
  local cost = math.floor(unit * qty * mult)

  -- Vérifie solde société
  local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
  if not row or (tonumber(row.money) or 0) < cost then
    return notify(src, { title='Réappro', description='Solde société insuffisant.', type='error' })
  end

  -- Débit société + +stock
  removeSocietyMoney(cost, account)
  MySQL.update.await('UPDATE vehicles SET stock = stock + ? WHERE model = ? OR name = ?', { qty, veh.model, veh.name })

  notify(src, { title='Réappro', description=('Stock +%d (%s) | -%s$'):format(qty, veh.name, cost), type='success' })
  addHistory(src, 'Réappro', cost, '/', veh.name)
end)
