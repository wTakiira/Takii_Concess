ESX = exports['es_extended']:getSharedObject()

-- ============== Helpers ==============
local SOCIETY_ACCOUNT = 'society_concess'
local DEFAULT_SOCIETY = 'society_concess'
local ALLOWED_PAYS    = { bank = true, money = true }
local DEALER_JOBS = {
  ['concess']   = true,  -- ton nom de job ?
}
local JOB_NAME = 'concess'
local MAX_GRADE = 4  

local function notify(src, data)
  if not src or src <= 0 then
    print(('[Concess][notify] src invalide: %s | title=%s | desc=%s'):format(
      tostring(src), tostring(data and data.title), tostring(data and data.description)
    ))
    return
  end
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

-- ===== Détection framework simple
local isESX, isQB = false, false
CreateThread(function()
  if GetResourceState('es_extended') == 'started' then isESX = true end
  if GetResourceState('qb-core')     == 'started' then isQB  = true end
end)

local function isDealerJob(jobName)
  return DEALER_JOBS[jobName or ''] == true
end

local function countDealersESX()
  local xPlayers = ESX.GetExtendedPlayers()
  local n = 0
  for _, xP in pairs(xPlayers) do
    if xP and xP.getJob and xP.getJob().name and isDealerJob(xP.getJob().name) then
      n = n + 1
    end
  end
  return n
end

local function countDealersQB()
  local players = QBCore.Functions.GetQBPlayers()
  local n = 0
  for _, p in pairs(players) do
    local jobName = p.PlayerData and p.PlayerData.job and p.PlayerData.job.name
    if isDealerJob(jobName) then n = n + 1 end
  end
  return n
end

local function getDealersOnline()
  if isESX and ESX and ESX.GetExtendedPlayers then return countDealersESX() end
  if isQB  and QBCore and QBCore.Functions and QBCore.Functions.GetQBPlayers then
    return countDealersQB()
  end
  -- Fallback ultra simple si aucun framework détecté
  local n = 0
  for _, id in ipairs(GetPlayers()) do
    -- à remplacer par ta logique custom si tu stockes le job autrement
    -- sinon on renvoie 0
  end
  return n
end

-- ox_lib callback pour le client
lib.callback.register('concess:getDealersOnline', function(source)
  return getDealersOnline()
end)

-- (Optionnel) broadcast live quand ça change
local function broadcastDealers()
  TriggerClientEvent('concess:dealers:update', -1, getDealersOnline())
end

-- Hooks “changement de job” pour rafraîchir en live
if isESX then
  AddEventHandler('esx:setJob', function(playerId, job, lastJob)
    broadcastDealers()
  end)
  AddEventHandler('playerDropped', function() broadcastDealers() end)
  AddEventHandler('esx:playerLoaded', function(playerId, xPlayer, isNew) broadcastDealers() end)
elseif isQB then
  RegisterNetEvent('QBCore:Server:OnJobUpdate', function(src, job)
    broadcastDealers()
  end)
  AddEventHandler('playerDropped', function() broadcastDealers() end)
  AddEventHandler('QBCore:Server:PlayerLoaded', function(player) broadcastDealers() end)
end



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


-- ——— Allocation locale (serveur) réutilisable
local function AllocPlateABC1234_server()
    for _ = 1, 80 do
        local plate = makePlateABC1234()
        if not PlateReservations[plate] and not plateExistsDB(plate) then
            PlateReservations[plate] = GetGameTimer() + RESERVE_TTL_MS
            return plate
        end
    end
    return false
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


RegisterNetEvent('Takii_Concess:createInvoiceForNearest', function(targetServerId, meta)
    local src = source
    local xSrc = ESX.GetPlayerFromId(src)

    if not targetServerId or type(targetServerId) ~= 'number' then
        TriggerClientEvent('Takii_Concess:invoiceResult', src, false, 'Client invalide.')
        return
    end
    if GetResourceState('Takii_Invoice') ~= 'started' then
        TriggerClientEvent('Takii_Concess:invoiceResult', src, false, 'Takii_Invoice non démarré.')
        return
    end

    meta = meta or {}
    meta.issuerSource     = src
    meta.issuerName       = meta.issuerName or (xSrc and xSrc.getName() or 'Concession')
    -- Optionnel: forcer la société si besoin (sinon auto via config côté Takii_Invoice)
    -- meta.issuerJob    = 'concess'

    local ok, err = exports['Takii_Invoice']:GiveInvoice(targetServerId, meta)
    if not ok then
        TriggerClientEvent('Takii_Concess:invoiceResult', src, false, ('Erreur: %s'):format(err or 'inconnue'))
        return
    end

    TriggerClientEvent('Takii_Concess:invoiceResult', src, true, 'Facture envoyée au client.')
end)



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


-- ====== LIVRAISON / MISSION LOCK PAR CONCESSION ======
local ActiveRepo = {}  -- ActiveRepo[shopId] = { [playerSrc] = { model=..., remaining=... } }

local function hasActiveRepo(src, shopId)
    ActiveRepo[shopId] = ActiveRepo[shopId] or {}
    return ActiveRepo[shopId][src] ~= nil
end

local function startRepo(src, shopId, model, count)
    ActiveRepo[shopId] = ActiveRepo[shopId] or {}
    ActiveRepo[shopId][src] = { model = model, remaining = count }
end

local function finishRepoIfDone(src, shopId)
    ActiveRepo[shopId] = ActiveRepo[shopId] or {}
    local st = ActiveRepo[shopId][src]
    if not st then return end
    if st.remaining <= 0 then
        ActiveRepo[shopId][src] = nil
        TriggerClientEvent('ox_lib:notify', src, { title='Livraison', type='success', description='Mission terminée.' })
    end
end

-- DÉMARRER une mission (depuis UI/PNJ) : appelle ce serveur au lieu d’appeler direct le client
RegisterNetEvent('concess:repo:startServer', function(shopId, model, count)
    local src = source
    shopId = shopId or 'default'
    count = math.min(tonumber(count) or 1, 5); if count < 1 then count = 1 end

    if hasActiveRepo(src, shopId) then
        TriggerClientEvent('ox_lib:notify', src, { title='Livraison', type='error', description='Vous avez déjà une livraison en cours pour cette concession.' })
        return
    end

    -- lock
    startRepo(src, shopId, model, count)

    -- envoie au client le démarrage avec le nombre à spawn
    TriggerClientEvent('concess:repo:startClient', src, { model = model, count = count })
end)

-- RETOUR d’UN véhicule : +1 stock et décrémente le compteur
RegisterNetEvent('concess:repo:returnOne', function(payload)
    local src = source
    local shopId = payload and payload.shopId or 'default'
    local model  = payload and payload.model

    ActiveRepo[shopId] = ActiveRepo[shopId] or {}
    local st = ActiveRepo[shopId][src]

    -- sécurité: forcer le modèle
    local usedModel = payload.model or model
    print(usedModel)

    -- +1 au stock du modèle
    MySQL.update.await('UPDATE vehicles SET stock = stock + 1 WHERE model = ? OR name = ?', { usedModel, usedModel })
    print('+1 stock')

    -- -- décrémente le restant
    -- st.remaining = (st.remaining or 1) - 1

    -- historique optionnel
    local row = MySQL.single.await('SELECT name FROM vehicles WHERE model = ? OR name = ? LIMIT 1', { usedModel, usedModel })
    addHistory(src, 'Retour livraison', '/', '/', (row and row.name) or usedModel)

    -- feedback
    TriggerClientEvent('ox_lib:notify', src, { title='Livraison', type='success', description=('Déposé: %s | Restants: %d'):format((row and row.name) or usedModel) })

    -- terminé ?
    finishRepoIfDone(src, shopId)
end)



local PendingSales = {} -- [payerSrc] = { issuerSrc, plate, spawnName, vehicleModel, lines, total }

-- util: hash/model
local function getModelHash(spawnName)
    if not spawnName or spawnName == '' then return nil end
    return joaat(spawnName)
end

-- ---- Spawn depuis le Config (catalogue.spawn) ----
local DEFAULT_SPOT = vector4(135.0231, -1094.0894, 29.1951, 102.0680)

local function _toV4FromSpawn(spawn)
    if not spawn or not spawn.coords then return nil end
    local c = spawn.coords
    local h = spawn.heading or spawn.h or 0.0
    if type(c) == 'vector3' then
        return vector4(c.x, c.y, c.z, h)
    elseif type(c) == 'table' then
        local x = c.x or c[1]
        local y = c.y or c[2]
        local z = c.z or c[3]
        if x and y and z then return vector4(x, y, z, h) end
    end
    return nil
end

local function getConfiguredSpawn(shopId)
    if Config and Config.Shops and shopId and Config.Shops[shopId]
        and Config.Shops[shopId].catalogue and Config.Shops[shopId].catalogue.spawn then
        local v4 = _toV4FromSpawn(Config.Shops[shopId].catalogue.spawn)
        if v4 then return v4 end
    end
    if Config and Config.catalogue and Config.catalogue.spawn then
        local v4 = _toV4FromSpawn(Config.catalogue.spawn)
        if v4 then return v4 end
    end
    return DEFAULT_SPOT
end


-- util: presets couleur → soit indices GTA, soit RGB custom
local function applyColorPreset(veh, preset, rgb)
    if preset == 'noir_mat' then
        SetVehicleColours(veh, 0, 0) -- black indices
        SetVehicleExtraColours(veh, 0, 0)
        SetVehicleModKit(veh, 0)
        SetVehicleMod(veh, 55, 1) -- peintures? (optionnel)
        SetVehicleXenonLightsColor(veh, 255)
        SetVehicleCustomPrimaryColour(veh, 0, 0, 0)
        SetVehicleCustomSecondaryColour(veh, 0, 0, 0)
    elseif preset == 'blanc' then
        SetVehicleCustomPrimaryColour(veh, 255, 255, 255)
        SetVehicleCustomSecondaryColour(veh, 255, 255, 255)
    elseif preset == 'rouge' then
        SetVehicleCustomPrimaryColour(veh, 200, 20, 20)
        SetVehicleCustomSecondaryColour(veh, 200, 20, 20)
    elseif preset == 'bleu' then
        SetVehicleCustomPrimaryColour(veh, 20, 60, 200)
        SetVehicleCustomSecondaryColour(veh, 20, 60, 200)
    elseif preset == 'vert' then
        SetVehicleCustomPrimaryColour(veh, 20, 180, 60)
        SetVehicleCustomSecondaryColour(veh, 20, 180, 60)
    elseif preset == 'custom' and rgb and rgb.r and rgb.g and rgb.b then
        SetVehicleCustomPrimaryColour(veh, rgb.r, rgb.g, rgb.b)
        SetVehicleCustomSecondaryColour(veh, rgb.r, rgb.g, rgb.b)
    else
        -- stock: rien
    end
end

-- >>> Ouvrir la facture chez le joueur
RegisterNetEvent('Takii_Concess:openInvoiceForNearest', function(targetId, meta)
    local src = source
    if GetResourceState('Takii_Invoice') ~= 'started' then
        TriggerClientEvent('Takii_Concess:invoiceResult', src, false, 'Takii_Invoice non démarré.')
        return
    end

    meta = meta or {}
    local lines = meta.lines or {}
    local total = 0
    for _,ln in ipairs(lines) do total = total + ((tonumber(ln.qty) or 0)*(tonumber(ln.unit) or 0)) end
    if (tonumber(meta.vatRate) or 0) > 0 then total = total + (total * tonumber(meta.vatRate)) end

    -- stocker la vente (pour suite)
    PendingSales[targetId] = {
        issuerSrc = src,
        plate = meta.plate or '',
        spawnName = meta.spawnName or '', -- code spawn (important)
        vehicleModel = meta.vehicleModel or '',
        lines = lines,
        total = total,
        shopId = meta.shopId 
    }

    local ok, err = exports['Takii_Invoice']:OpenInvoice(targetId, meta)
    TriggerClientEvent('Takii_Concess:invoiceResult', src, ok, ok and 'Facture ouverte.' or ('Erreur: '..(err or '')))
end)

-- >>> Après paiement (event global du script facture)
AddEventHandler('takii_invoice:paid', function(data)
    -- data: payerSource, method, total, plate?, vehicleModel?, issuerSource?, ...
    local sale = PendingSales[data.payerSource]
    if not sale then return end
    -- (option) vérifier la cohérence de la plaque
    if sale.plate ~= '' and data.plate and data.plate ~= sale.plate then
        print(('[Takii_Concess] Avertissement: plate mismatch %s vs %s'):format(tostring(data.plate), tostring(sale.plate)))
    end

    -- demander la couleur côté client payeur
    TriggerClientEvent('Takii_Concess:chooseColor', sale.issuerSrc, { payer = data.payerSource })
end)


-- >>> Le vendeur a choisi la couleur → on livre AU CLIENT (payer): spawn + clés + DB
RegisterNetEvent('Takii_Concess:colorChosen', function(sel)
    local sellerSrc = source
    local payer     = sel and tonumber(sel.payer)
    local choice    = (sel and sel.choice) or 'stock'
    print(('[Concess] colorChosen seller=%s payer=%s choice=%s'):format(sellerSrc, payer or 'nil', choice or 'nil'))

    if not payer then return end
    local sale = PendingSales[payer]
    if not sale then
        TriggerClientEvent('esx:showNotification', sellerSrc, 'Vente introuvable ou expirée.')
        print('[Concess] ! no PendingSales for payer:', payer)
        return
    end

    local modelName = sale.spawnName or sale.vehicleModel
    local modelHash = modelName and joaat(modelName) or nil
    if not modelHash then
        TriggerClientEvent('esx:showNotification', sellerSrc, 'Modèle introuvable (spawnName manquant).')
        print('[Concess] ! missing modelName')
        PendingSales[payer] = nil
        return
    end

    -- 1) Plaque ABC 1234 via la fonction locale (aucun callback)
    local plate = sale.plate
    if not (type(plate) == 'string' and plate:match('^%u%u%u %d%d%d%d$')) then
        plate = AllocPlateABC1234_server()
    end
    if not plate then
        TriggerClientEvent('esx:showNotification', sellerSrc, 'Impossible de générer une plaque.')
        print('[Concess] ! plate allocation failed')
        PendingSales[payer] = nil
        return
    end
    sale.plate = plate
    print('[Concess] plate=', plate)

    -- 2) INSERT d’abord en DB (ligne minimale)
    local xBuyer = ESX.GetPlayerFromId(payer)
    if not xBuyer then print('[Concess] ! buyer offline'); return end

    local minimal = json.encode({ plate = plate, model = modelName })
    local okIns, errIns = pcall(function()
        MySQL.insert.await(
            'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, ?)',
            { xBuyer.identifier, plate, minimal, 'vehicle', 0 }
        )
        MySQL.update.await(
          'UPDATE vehicles SET stock = stock - 1 WHERE (model = ? OR name = ?) AND stock > 0',
          { modelName, modelName }
      )
    end)
    print('[Concess] INSERT owned_vehicles ->', okIns and 'OK' or ('ERR '..tostring(errIns)))
    if not okIns then
        TriggerClientEvent('esx:showNotification', sellerSrc, 'Erreur enregistrement véhicule (INSERT).')
        PendingSales[payer] = nil
        return
    end

    -- 3) Spawn au point Config
    local spot   = getConfiguredSpawn and getConfiguredSpawn(sale.shopId) or vector4(135.0231, -1094.0894, 29.1951, 102.0680)
    local coords = vector3(spot.x, spot.y, spot.z)
    local head   = spot.w or 0.0
    print('[Concess] spawn', modelName, ('x%.2f y%.2f z%.2f h%.2f'):format(coords.x, coords.y, coords.z, head))

    local function afterSpawn(netId)
        print('[Concess] spawn cb netId=', netId)
        if not netId or netId == 0 then
            TriggerClientEvent('esx:showNotification', sellerSrc, 'Erreur de spawn véhicule.')
            print('[Concess] ! spawn failed')
            return
        end

        local veh = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(veh) then
            SetVehicleNumberPlateText(veh, plate)
            if choice == 'noir_mat' then
                SetVehicleCustomPrimaryColour(veh, 0, 0, 0); SetVehicleCustomSecondaryColour(veh, 0, 0, 0)
            elseif choice == 'blanc' then
                SetVehicleCustomPrimaryColour(veh, 255,255,255); SetVehicleCustomSecondaryColour(veh, 255,255,255)
            elseif choice == 'rouge' then
                SetVehicleCustomPrimaryColour(veh, 200,20,20); SetVehicleCustomSecondaryColour(veh, 200,20,20)
            elseif choice == 'bleu' then
                SetVehicleCustomPrimaryColour(veh, 20,60,200); SetVehicleCustomSecondaryColour(veh, 20,60,200)
            elseif choice == 'vert' then
                SetVehicleCustomPrimaryColour(veh, 20,180,60); SetVehicleCustomSecondaryColour(veh, 20,180,60)
            end
        else
            print('[Concess] ! entity not exist after spawn')
        end

        -- 4) Demande au CLIENT d’envoyer les props pour UPDATE
        TriggerClientEvent('Takii_Concess:captureProps', payer, {
            netId = netId, plate = plate, model = modelName,
            sale  = { price = sale.total, label = sale.vehicleModel or modelName, shopId = sale.shopId }
        })

        -- Clés au CLIENT immédiatement (DB déjà insérée)
        local okKeys, errKeys = pcall(function()
            exports['qs-vehiclekeys']:GiveServerKeys(payer, plate, modelName or 'car', true)
        end)
        print('[Concess] keys ->', okKeys and 'OK' or ('ERR '..tostring(errKeys)))

        if sale.issuerSrc then
            TriggerClientEvent('esx:showNotification', sale.issuerSrc,
                ('Véhicule livré: %s [%s]. Finalisation en cours...'):format(sale.vehicleModel or modelName, plate))
        end
        TriggerClientEvent('esx:showNotification', payer, 'Véhicule livré. Clés remises. Finalisation...')
    end

    if ESX.OneSync and ESX.OneSync.SpawnVehicle then
        ESX.OneSync.SpawnVehicle(modelHash, coords, head, { plate = plate }, afterSpawn)
    else
        print('[Concess] ! ESX.OneSync.SpawnVehicle indisponible, fallback CreateVehicle')
        local veh = CreateVehicle(modelHash, coords.x, coords.y, coords.z, head, true, true)
        local tries, netId = 0, 0
        while tries < 50 and (not veh or not DoesEntityExist(veh)) do Wait(50); tries = tries + 1 end
        if veh and DoesEntityExist(veh) then
            netId = NetworkGetNetworkIdFromEntity(veh)
        end
        afterSpawn(netId)
    end
end)


-- reçoit les props du client et enregistre en BDD + clés
RegisterNetEvent('Takii_Concess:storeOwned', function(payload)
    local src = source -- client payeur
    local sale = PendingSales[src]
    print('[Concess] storeOwned src=', src, 'payload=', payload and 'yes' or 'nil')
    if not sale then print('[Concess] ! no pending sale for', src) return end

    local props = payload and payload.props or {}
    local plate = (props and props.plate) or (payload and payload.plate) or ''
    if type(plate) ~= 'string' or plate == '' then print('[Concess] ! invalid plate in storeOwned') return end

    local xBuyer = ESX.GetPlayerFromId(src)
    if not xBuyer then print('[Concess] ! buyer offline in storeOwned') return end

    local vehicleJson = json.encode(props or { plate = plate, model = sale.spawnName or sale.vehicleModel })
    print('[Concess] UPDATE owned_vehicles, plate=', plate)

    local okUp, errUp = pcall(function()
        MySQL.update.await('UPDATE owned_vehicles SET vehicle = ? WHERE plate = ?', { vehicleJson, plate })
    end)
    print('[Concess] UPDATE ->', okUp and 'OK' or ('ERR '..tostring(errUp)))
    if not okUp then
        TriggerClientEvent('esx:showNotification', src, 'Erreur finalisation enregistrement.')
        return
    end

    TriggerEvent('Takii_Concess:registerVehicle', {
        ownerSource = src, spawnName = sale.spawnName, plate = plate,
        netId = payload.netId, vehicleModel = sale.vehicleModel, price = sale.total
    })

    if sale.issuerSrc then
        TriggerClientEvent('esx:showNotification', sale.issuerSrc,
            ('Vente finalisée: %s [%s], total %s$.'):format(sale.vehicleModel or (sale.spawnName or 'vehicule'), plate, sale.total))
    end
    TriggerClientEvent('esx:showNotification', src, 'Enregistrement terminé.')
    PendingSales[src] = nil
end)




-- >>> Si le client ferme la facture sans payer
AddEventHandler('takii_invoice:cancelled', function(data)
    local payer = data and data.payerSource
    local sale = payer and PendingSales[payer] or nil
    if sale then
        if sale.issuerSrc then
            TriggerClientEvent('esx:showNotification', sale.issuerSrc, 'Le client a annulé la facture.')
        end
        PendingSales[payer] = nil
    end
end)



-- ===== Utilitaires boss =====
local function getSocietyBalance(account)
  account = account or SOCIETY_ACCOUNT
  print(('[boss] getSocietyBalance(%s)'):format(account))
  local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
  local bal = row and (tonumber(row.money) or 0) or 0
  print(('[boss] balance=%s'):format(bal))
  return bal
end

local function addMoneyOffline(identifier, account, amount)
  print(('[boss] addMoneyOffline id=%s account=%s amount=%s'):format(
    tostring(identifier), tostring(account), tostring(amount)
  ))
  amount = tonumber(amount) or 0
  account = account or 'bank'
  if amount <= 0 then print('[boss] addMoneyOffline: amount <= 0'); return false end

  for _, id in ipairs(ESX.GetPlayers()) do
    local xP = ESX.GetPlayerFromId(id)
    if xP and xP.identifier == identifier then
      print('[boss] joueur en ligne, crédit direct')
      xP.addAccountMoney(account, amount)
      return true
    end
  end

  print('[boss] joueur offline, update JSON accounts')
  local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ? LIMIT 1', { identifier })
  if not row then print('[boss] users row introuvable'); return false end
  local accounts = {}
  if row.accounts and row.accounts ~= '' then
    local ok, parsed = pcall(json.decode, row.accounts)
    if ok and type(parsed) == 'table' then accounts = parsed end
  end
  accounts[account] = tonumber(accounts[account] or 0) + amount
  local aff = MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(accounts), identifier })
  print(('[boss] UPDATE users.accounts affected=%s'):format(tostring(aff)))
  return true
end

lib.callback.register('ui:getNearby', function(source, data)
  print(('[boss] ui:getNearby src=%s max=%.2f'):format(tostring(source), (data and tonumber(data.max)) or 8.0))
  -- (reste inchangé)
end)

lib.callback.register('boss:getData', function(source)
  print(('[boss] boss:getData src=%s'):format(tostring(source)))
  local balance = getSocietyBalance(SOCIETY_ACCOUNT)
  local employees = MySQL.query.await(
    'SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ? ORDER BY job_grade DESC, lastname',
    { 'concess' }
  ) or {}
  print(('[boss] employees=%d'):format(#employees))
  local salaries = MySQL.query.await(
    'SELECT grade, label, salary FROM job_grades WHERE job_name = ? ORDER BY grade',
    { 'concess' }
  ) or {}
  print(('[boss] salaries=%d'):format(#salaries))
  return { balance=balance, employees=employees, salaries=salaries }
end)

-- Payer un salarié (débit société -> crédit banque joueur, offline OK)
RegisterNetEvent('boss:payCustom', function(payload)
  local src = source
  local identifier = payload and payload.identifier
  local amount     = payload and tonumber(payload.amount or 0) or 0
  print(('[boss:payCustom] src=%s identifier=%s amount=%s'):format(tostring(src), tostring(identifier), tostring(amount)))
  if not identifier or amount <= 0 then print('[boss:payCustom] invalid args'); return end

  if not removeSocietyMoney(amount, SOCIETY_ACCOUNT) then
    print('[boss:payCustom] removeSocietyMoney FAILED')
    return notify(src, { title='Paie', description='Solde société insuffisant.', type='error' })
  end

  local ok = addMoneyOffline(identifier, 'bank', amount)
  print(('[boss:payCustom] addMoneyOffline=%s'):format(ok and 'OK' or 'FAIL'))

  if not ok then
    addSocietyMoney(amount, SOCIETY_ACCOUNT)
    return notify(src, { title='Paie', description='Impossible de créditer le salarié.', type='error' })
  end
  notify(src, { title='Paie', description=('Payé %s$'):format(amount), type='success' })
end)

-- ===== Utils ESX: setJob pour online/offline =====
local function getXPlayerByIdentifier(identifier)
  for _, id in ipairs(ESX.GetPlayers()) do
    local xP = ESX.GetPlayerFromId(id)
    if xP and xP.identifier == identifier then
      return xP, id
    end
  end
  return nil, nil
end

local function setJobPersist(identifier, job, grade)
  grade = tonumber(grade) or 0
  local xP, pid = getXPlayerByIdentifier(identifier)
  if xP then
    print(('[BOSS:setJobPersist] ONLINE %s -> %s %s'):format(identifier, job, grade))
    xP.setJob(job, grade)
    return true, 'online'
  else
    print(('[BOSS:setJobPersist] OFFLINE %s -> %s %s'):format(identifier, job, grade))
    MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { job, grade, identifier })
    return true, 'offline'
  end
end

local function setGradePersist(identifier, newGrade)
  newGrade = tonumber(newGrade) or 0
  local xP = getXPlayerByIdentifier(identifier)
  if xP then
    print(('[BOSS:setGradePersist] ONLINE %s -> grade %s (job=%s)'):format(identifier, newGrade, xP.getJob().name))
    xP.setJob(xP.getJob().name, newGrade)
    return true, 'online'
  else
    print(('[BOSS:setGradePersist] OFFLINE %s -> grade %s'):format(identifier, newGrade))
    MySQL.update.await('UPDATE users SET job_grade = ? WHERE identifier = ?', { newGrade, identifier })
    return true, 'offline'
  end
end

-- ====== CHANGE GRADE (↑/↓ exact) ======
RegisterNetEvent('boss:changeGrade', function(data)
  local src = source
  local identifier = data and data.identifier
  local newGrade   = data and tonumber(data.newGrade or -1) or -1
  print(('[boss:changeGrade] src=%s identifier=%s newGrade=%s'):format(src, tostring(identifier), tostring(newGrade)))
  if not identifier or newGrade < 0 then print('[boss:changeGrade] invalid args'); return end

  local ok, where = setGradePersist(identifier, newGrade)
  print(('[boss:changeGrade] result=%s where=%s'):format(tostring(ok), tostring(where)))
  notify(src, { title='Grade', description=('Nouveau grade: %d (%s)'):format(newGrade, where), type='success' })

  -- option: ping UI pour recharger
  TriggerClientEvent('concess:boss:refresh', src)
end)

-- ====== PROMOTE TO BOSS (4) + demote actuel boss (3) ======
RegisterNetEvent('boss:promoteToBoss', function(data)
  local src = source
  local identifier = data and data.identifier
  print(('[boss:promoteToBoss] src=%s identifier=%s'):format(src, tostring(identifier)))
  if not identifier then print('[boss:promoteToBoss] invalid args'); return end

  -- Rétrograder tous les patrons (grade 4) -> 3, online + offline
  -- Online d’abord
  for _, id in ipairs(ESX.GetPlayers()) do
    local xP = ESX.GetPlayerFromId(id)
    if xP and xP.getJob().name == 'concess' and tonumber(xP.getJob().grade) == 4 then
      print(('[boss:promoteToBoss] demote ONLINE %s'):format(xP.identifier))
      xP.setJob('concess', 3)
    end
  end
  -- Offline
  local aff1 = MySQL.update.await('UPDATE users SET job_grade = 3 WHERE job = ? AND job_grade = 4', { 'concess' })
  print(('[boss:promoteToBoss] demote offline affected=%s'):format(tostring(aff1)))

  -- Promouvoir la cible
  local ok, where = setJobPersist(identifier, 'concess', 4)
  print(('[boss:promoteToBoss] promote result=%s where=%s'):format(tostring(ok), tostring(where)))

  notify(src, { title='Direction', description='Nouveau patron défini (grade 4).', type='success' })
  TriggerClientEvent('concess:boss:refresh', src)
end)

-- ====== FIRE -> unemployed 0 ======
RegisterNetEvent('boss:fire', function(data)
  local src = source
  local identifier = data and data.identifier
  print(('[boss:fire] src=%s identifier=%s'):format(src, tostring(identifier)))
  if not identifier then print('[boss:fire] invalid args'); return end

  local ok, where = setJobPersist(identifier, 'unemployed', 0)
  print(('[boss:fire] result=%s where=%s'):format(tostring(ok), tostring(where)))
  notify(src, { title='Employés', description='Employé renvoyé (unemployed 0).', type='success' })
  TriggerClientEvent('concess:boss:refresh', src)
end)

-- ====== RECRUIT (joueur proche) -> concess, grade X ======
RegisterNetEvent('boss:recruit', function(data)
  local src   = source
  local targetId = data and tonumber(data.targetId)
  local grade    = data and tonumber(data.grade or 0) or 0
  print(('[boss:recruit] src=%s targetId=%s grade=%s'):format(src, tostring(targetId), tostring(grade)))
  if not targetId then
    notify(src, { title='Recrutement', description='Joueur introuvable.', type='error' })
    return
  end

  if grade < 0 or grade > MAX_GRADE then
    notify(src, { title='Recrutement', description='Grade invalide.', type='error' })
    return
  end

  local tgt = ESX.GetPlayerFromId(targetId)
  if not tgt then
    notify(src, { title='Recrutement', description='Joueur hors ligne.', type='error' })
    return
  end
  local target = GetPlayerIdentifiers(targetId)
  print(('[boss:recruit] ONLINE identifier=%s'):format(tgt.identifier))
  print(JOB_NAME, grade)
   MySQL.update('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', {
      'concess', grade, tgt.identifier
  })

  tgt.setJob(JOB_NAME, grade)

 
  

  -- contrôle post-set (débogage utile)
  local after = tgt.getJob()
  print(('[boss:recruit] after setJob: name=%s grade=%s'):format(after.name, tostring(after.grade)))

  print(after.name,JOB_NAME,after.grade,grade)
  if after and after.name == JOB_NAME and tonumber(after.grade) == grade then
    notify(src,     { title='Recrutement', description=('Recruté %s (grade %d)'):format(GetPlayerName(targetId), grade), type='success' })
    notify(targetId,{ title='Emploi',       description=('Vous avez été recruté: %s (grade %d)'):format(JOB_NAME, grade), type='success' })
    TriggerClientEvent('concess:boss:refresh', src)
  else
    notify(src, { title='Recrutement', description='Échec setJob (vérifie le nom du job et les grades).', type='error' })
  end
end)




RegisterNetEvent('boss:addMoney', function(payload)
  local src = source
  local amount = payload and tonumber(payload.amount or 0) or 0
  print(('[boss:addMoney] src=%s amount=%s'):format(tostring(src), tostring(amount)))
  if amount <= 0 then print('[boss:addMoney] amount <= 0'); return end

  local xP = ESX.GetPlayerFromId(src)
  if not xP then print('[boss:addMoney] xPlayer nil'); return end

  local cash = xP.getAccount('money').money or 0
  print(('[boss:addMoney] player cash=%s'):format(cash))
  if cash < amount then
    notify(src, { title='Compte entreprise', description="Montant insuffisant en espèces.", type='error' })
    print('[boss:addMoney] insufficient cash')
    return
  end

  xP.removeAccountMoney('money', amount)
  local ok = addSocietyMoney(amount, SOCIETY_ACCOUNT)
  print(('[boss:addMoney] addSocietyMoney=%s'):format(ok and 'OK' or 'FAIL'))
  notify(src, { title='Compte entreprise', description=('Dépôt effectué: +%s$'):format(amount), type='success' })
end)

RegisterNetEvent('boss:removeMoney', function(payload)
  local src = source
  local amount = payload and tonumber(payload.amount or 0) or 0
  print(('[boss:removeMoney] src=%s amount=%s'):format(tostring(src), tostring(amount)))
  if amount <= 0 then print('[boss:removeMoney] amount <= 0'); return end

  local ok = removeSocietyMoney(amount, SOCIETY_ACCOUNT)
  print(('[boss:removeMoney] removeSocietyMoney=%s'):format(ok and 'OK' or 'FAIL'))
  if not ok then
    notify(src, { title='Compte entreprise', description='Solde société insuffisant.', type='error' })
    return
  end

  local xP = ESX.GetPlayerFromId(src)
  if xP then xP.addAccountMoney('money', amount) end
  notify(src, { title='Compte entreprise', description=('Retrait effectué: -%s$'):format(amount), type='success' })
end)


