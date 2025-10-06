---@diagnostic disable: param-type-mismatch
ESX = exports['es_extended']:getSharedObject()
-- === Compat multi-shop: shim des anciens champs ===
Config = Config or {}
local uiReady = false

-- Forward declarations pour que les closures d'ox_target capturent des locales
local OpenCatalogUI, OpenCounterUI, OpenBossUI
local GetShop, StartLivraison 
local CAR_CLASSES = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[9]=true,[12]=true }
local Hauler = { veh = 0, trailer = 0 }

local function getLivraison()
    local s = GetShop()
    if not s or not s.livraison then return nil end
    local L = s.livraison

    -- rétro-compat: anciens noms -> nouveaux
    local pickup = L.pickup or L.toDelivery        -- pickup = où l'on va RECUPERER
    local depot  = L.depot  or L.destination       -- depot  = où l'on LIVRE au final
    local spawnTruck   = (L.spawn and L.spawn.truck)   or L.spawnTruck or L.spawn   -- accepte vec4 direct ou table
    local spawnTrailer = (L.spawn and L.spawn.trailer) or L.spawnTrailer            -- facultatif

    return {
        pickup = pickup, depot = depot,
        spawnTruck = spawnTruck, spawnTrailer = spawnTrailer,
        haulers = L.haulers, trailers = L.trailers,
        stock = L.stock
    }
end

local function ensurePlacedOnGround(ent)
    if not ent or ent == 0 then return end
    local c = GetEntityCoords(ent)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    for _=1,50 do
        if HasCollisionLoadedAroundEntity(ent) then break end
        Wait(10)
    end
    SetVehicleOnGroundProperly(ent)
    PlaceObjectOnGroundProperly(ent)
end

local CONCESS_DEBUG = true
local function dprint(...) if CONCESS_DEBUG then print('[CONCESS][REPO]', ...) end end
local function dnotify(msg) if CONCESS_DEBUG then lib.notify({title='[DEBUG] Repo', description=tostring(msg), type='inform'}) end end

-- si aucun shop actif, bascule sur le + proche (pour getLivraison)
local function ensureCurrentShopForRepo()
    if not CURRENT_SHOP then
        local id = NearestShopId(1000.0)
        if id then CURRENT_SHOP = id end
    end
    return getLivraison()
end

-- ===== FLATBED ONLY / helpers =====
local function ensureModelLoadedByName(name)
    local h = joaat(name)
    if not IsModelInCdimage(h) or not IsModelAVehicle(h) then return false, h end
    RequestModel(h)
    local tries=0
    while not HasModelLoaded(h) do
        tries = tries + 1
        if tries > 500 then return false, h end -- 5s
        Wait(10)
    end
    return true, h
end


-- Spawn camion (vehName) + remorque (trailerName optionnel)
local function DoSpawnHauler(vehName, trailerName)
    local L = getLivraison()
    if not L or not L.spawnTruck then
        lib.notify({title='Logistique', description='Shop non configuré (spawn.truck / spawnTruck manquant).', type='error'})
        return false, 'no_spawn'
    end

    -- Clean ancien attelage
    if Hauler.veh ~= 0 and DoesEntityExist(Hauler.veh) then DeleteEntity(Hauler.veh) end
    if Hauler.trailer ~= 0 and DoesEntityExist(Hauler.trailer) then DeleteEntity(Hauler.trailer) end
    Hauler.veh, Hauler.trailer = 0, 0

    -- Choix des modèles (avec fallback raisonnable)
    local truckName = tostring(vehName or (L.haulers and L.haulers[1]) or 'flatbed')
    local okTruck, hTruck = ensureModelLoadedByName(truckName)
    if not okTruck then
        lib.notify({title='Utilitaire', description=("Modèle camion invalide: %s"):format(truckName), type='error'})
        return false, 'bad_truck'
    end

    local trailerName = tostring(trailerName or '')
    local hTrailer = 0
    if trailerName ~= '' then
        local okTr, hTr = ensureModelLoadedByName(trailerName)
        if not okTr then
            lib.notify({title='Utilitaire', description=("Modèle remorque invalide: %s"):format(trailerName), type='error'})
            -- on continue quand même sans remorque
            trailerName = ''
        else
            hTrailer = hTr
        end
    end

    -- Coords spawn
    local st = L.spawnTruck
    local tx, ty, tz, th = st.x, st.y, st.z, (st.w or 0.0)

    -- Spawn camion
    local truck = CreateVehicle(hTruck, tx, ty, tz, th, true, true)
    if truck == 0 then
        lib.notify({title='Utilitaire', description='Création du camion impossible.', type='error'})
        return false, 'create_truck_failed'
    end
    ensurePlacedOnGround(truck)
    SetEntityAsMissionEntity(truck, true, true)
    SetVehicleOnGroundProperly(truck)
    SetPedIntoVehicle(PlayerPedId(), truck, -1)

    -- Spawn remorque (optionnel)
    local trailer = 0
    if trailerName ~= '' and hTrailer ~= 0 then
        local spr = L.spawnTrailer
        local rx, ry, rz, rh
        if spr then
            rx, ry, rz, rh = spr.x, spr.y, spr.z, (spr.w or th)
        else
            -- offset derrière le camion si pas de point défini
            local d = 8.0
            local rad = math.rad(th)
            rx = tx - math.sin(rad)*d
            ry = ty + math.cos(rad)*d
            rz = tz
            rh = th
        end

        trailer = CreateVehicle(hTrailer, rx, ry, rz, rh, true, true)
        if trailer ~= 0 then
            ensurePlacedOnGround(trailer)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleOnGroundProperly(trailer)
            -- Atteler (petit délai pour être sûr que tout est en place)
            Wait(150)
            AttachVehicleToTrailer(truck, trailer, 1.0)
        else
            lib.notify({title='Utilitaire', description='Création de la remorque impossible. Camion seul spawné.', type='warning'})
        end
    end

    -- Mémorise l’attelage
    Hauler.veh, Hauler.trailer = truck, trailer
    -- (libérer mémoire des modèles)
    SetModelAsNoLongerNeeded(hTruck)
    if hTrailer ~= 0 then SetModelAsNoLongerNeeded(hTrailer) end

    return true
end



-- helper: choisir un shop même si on est loin / sans catalogue.coords
local function _probeCoords(s)
    if s.catalogue and s.catalogue.coords then return s.catalogue.coords end
    if s.livraison and s.livraison.pickup  then return s.livraison.pickup end
    if s.livraison and s.livraison.depot   then return s.livraison.depot end
    if s.blip and s.blip.pos               then return s.blip.pos end
    return nil
end

local function NearestShopId(maxDist)
    if not (Config and Config.Shops) then return nil end
    maxDist = maxDist or 40.0
    local p = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, 1e9
    for id, s in pairs(Config.Shops) do
        local c = _probeCoords(s)
        if c then
            local cx,cy,cz = c.x or c[1], c.y or c[2], c.z or c[3]
            local d = #(p - vec3(cx,cy,cz))
            if d < bestDist and d <= maxDist then best, bestDist = id, d end
        end
    end
    return best, bestDist
end

-- Remplace TOTALEMENT ta fonction removeKeys par celle-ci
local function removeKeys(plate, entity, modelHint)
    local rawPlate = plate or ''
    if rawPlate == '' and entity and DoesEntityExist(entity) then
        rawPlate = GetVehicleNumberPlateText(entity) or ''
    end
    if rawPlate == '' then return false end

    -- Déterminer un "model" accepté par QS
    local modelHash = 0
    if entity and DoesEntityExist(entity) then modelHash = GetEntityModel(entity) end
    if modelHash == 0 and type(modelHint) == 'number' then modelHash = modelHint end

    local modelSend = ''
    if modelHash ~= 0 then
        -- QS accepte typiquement le DisplayName (ex: "ADDER") ou le hash converti en string
        modelSend = GetDisplayNameFromVehicleModel(modelHash) or ''
    end
    if modelSend == '' and type(modelHint) == 'string' then modelSend = modelHint end
    if modelSend == '' and modelHash ~= 0 then modelSend = tostring(modelHash) end

    local ok = false

    -- QS VehicleKeys
    if GetResourceState and GetResourceState('qs-vehiclekeys') == 'started' then
        -- Essaye l'export (qui sur les versions récentes prend plate, model)
        local s1, r1 = pcall(function()
            return exports['qs-vehiclekeys']:RemoveKeys(rawPlate, modelSend)
        end)
        ok = s1 and (r1 ~= false)

        -- Fallback officiel: event serveur qui exige plaque + modèle
        if not ok then
            TriggerServerEvent('vehiclekeys:server:removekey', rawPlate, modelSend)
            ok = true
        end
    end

    -- QB VehicleKeys (pas de modèle requis)
    if (not ok) and GetResourceState and GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:RemoveKeys', rawPlate)
        ok = true
    end

    -- Fallback: verrouille le véhicule
    if entity and DoesEntityExist(entity) then
        SetVehicleDoorsLocked(entity, 2)
    end

    return ok
end


local function ensureCurrentShopForRepo(prefId)
    if prefId and Config.Shops[prefId] then CURRENT_SHOP = prefId end
    if not CURRENT_SHOP then
        local near = NearestShopId(2000.0)        -- large rayon
        if near then CURRENT_SHOP = near end
    end
    if not CURRENT_SHOP and Config.Shops then
        for id,s in pairs(Config.Shops) do
            if s.livraison and s.livraison.pickup then CURRENT_SHOP = id; break end
        end
        if not CURRENT_SHOP then for id,_ in pairs(Config.Shops) do CURRENT_SHOP = id; break end end
    end
    return getLivraison()
end


local function DoClearHauler()
    if Hauler.veh ~= 0 and DoesEntityExist(Hauler.veh) then DeleteEntity(Hauler.veh) end
    if Hauler.trailer ~= 0 and DoesEntityExist(Hauler.trailer) then DeleteEntity(Hauler.trailer) end
    Hauler.veh, Hauler.trailer = 0, 0
    return true
end

-- petit helper de sélection via ox_lib
local function selectFrom(list, label, placeholder)
    local opts = {}
    for _,v in ipairs(list or {}) do
        local l = (v.label or v.name or v.model)
        opts[#opts+1] = { value = v.model, label = l }
    end
    local input = lib.inputDialog(label or 'Sélection', {
        { type='select', label=label or 'Modèle', options=opts, required=true, placeholder=placeholder or 'Choisir...' }
    })
    if input and input[1] then return tostring(input[1]) end
    return nil
end

local function promptQty(default)
    local i = lib.inputDialog('Quantité', { { type='number', label='Quantité', required=true, min=1, step=1, default=default or 1 } })
    return i and tonumber(i[1]) or nil
end


-- Convertit un modèle (hash/nom) -> "Marque Modèle"
local prettyLabelFor
do
  local cache = {}
  prettyLabelFor = function(model)
    if not model then return '—' end
    if cache[model] then return cache[model] end
    local hash = type(model)=='string' and joaat(model) or model
    local makeKey = GetMakeNameFromVehicleModel(hash) or ''
    local nameKey = GetDisplayNameFromVehicleModel(hash) or ''
    local make = (makeKey ~= '' and GetLabelText(makeKey)) or makeKey
    local name = (nameKey ~= '' and GetLabelText(nameKey)) or nameKey
    if not make or make=='NULL' then make='' end
    if not name or name=='NULL' then name=tostring(model) end
    local out = (make~='' and (make..' '..name)) or name
    cache[model] = out
    return out
  end
end


local function isModelAllowedForSpot(spot, modelNameOrHash)
    if not spot or not spot.type then return true end      -- par défaut: tout
    local hash = (type(modelNameOrHash)=='string' and joaat(modelNameOrHash)) or modelNameOrHash
    local cls  = GetVehicleClassFromName(hash)
    if spot.type == 'bike' then
        return (cls == 8)  -- Motorcycles
    elseif spot.type == 'car' then
        return CAR_CLASSES[cls] == true
    end
    return true
end




-- Si on est en multi-shop, créer des valeurs par défaut pour les anciens accès
if Config.UseMulti and Config.Shops and not Config.Catalogue then
    -- Prendre n’importe quel shop comme fallback pour éviter les nil
    local first
    for _, s in pairs(Config.Shops) do first = s; break end

    if first and first.catalogue then
        local spawn  = (first.catalogue.spawn or {})
        local prev   = (first.catalogue.preview or {})
        local cam    = (first.catalogue.cam or first.catalogue.camera or {})

        Config.Catalogue = {
            SpawnVehicle = {
                coords  = (spawn.coords or first.catalogue.coords or vector3(0,0,0)),
                heading = (spawn.heading or (first.catalogue.coords and first.catalogue.coords.w) or 0.0)
            }
        }

        Config.Preview = Config.Preview or {}
        Config.Preview.SpawnVehicle = Config.Preview.SpawnVehicle or {
            coords  = (prev.coords or Config.Catalogue.SpawnVehicle.coords or vector3(0,0,0)),
            heading = (prev.heading or Config.Catalogue.SpawnVehicle.heading or 0.0)
        }
        Config.Preview.Cam = Config.Preview.Cam or {
            coords  = (cam.coords or vector3(0,0,0)),
            heading = (cam.heading or 0.0)
        }
    else
        -- Dernier filet de sécurité
        Config.Catalogue = { SpawnVehicle = { coords = vector3(0,0,0), heading = 0.0 } }
        Config.Preview   = { SpawnVehicle = { coords = vector3(0,0,0), heading = 0.0 }, Cam = { coords = vector3(0,0,0), heading = 0.0 } }
    end
end


-- =========================================================
-- ===============   MULTI-CONCESS / HELPERS   =============
-- =========================================================
local CURRENT_SHOP = nil
local nuiOpen      = false
local previewVeh   = nil
local previewCam   = nil

local function IsDealerJob()
    local job = ESX and ESX.PlayerData and ESX.PlayerData.job and ESX.PlayerData.job.name
    if not job then return false end
    if Config.AllowedJobs then for _,j in ipairs(Config.AllowedJobs) do if j==job then return true end end end
    if Config.Shops then for _,s in pairs(Config.Shops) do if (s.jobs and s.jobs[job]) or s.job==job then return true end end end
    return (Config.AllowedJob and job==Config.AllowedJob) or (Config.Job and job==Config.Job)
end

local function IsEmployeeForShop(shopId)
    local job = ESX and ESX.PlayerData and ESX.PlayerData.job and ESX.PlayerData.job.name
    if not job or not Config.Shops or not Config.Shops[shopId] then return false end
    local s = Config.Shops[shopId]
    if s.jobs and s.jobs[job] then return true end        -- table de jobs autorisés
    if s.job and s.job == job then return true end        -- job unique
    return false
end

local function IsBossJob()
    local jd = ESX and ESX.PlayerData and ESX.PlayerData.job
    if not jd then return false end
    return (jd.grade_name and jd.grade_name:lower() == 'boss') or (jd.grade and jd.grade >= (Config.BossMinGrade or 4))
end

local function NearestShopId(maxDist)
    if not (Config and Config.Shops) then return nil end
    maxDist = maxDist or 40.0
    local p=GetEntityCoords(PlayerPedId())
    local best,dist=nil,1e9
    for id,s in pairs(Config.Shops) do
        local c=s.catalogue and s.catalogue.coords
        if c then
            local d = #(p - vec3(c.x,c.y,c.z))
            if d<dist and d<=maxDist then best,dist=id,d end
        end
    end
    return best,dist
end

GetShop = function()
    if CURRENT_SHOP and Config.Shops and Config.Shops[CURRENT_SHOP] then
        return Config.Shops[CURRENT_SHOP]
    end
    local id = NearestShopId(100.0)
    return (id and Config.Shops[id]) or nil
end


OpenCounterUI = function()
    if nuiOpen then return end
    nuiOpen = true

    local shop = GetShop()
    local shopLabel = shop and (shop.label or "Concession") or "Concession"

    SetNuiFocus(true, true)
    if not uiReady then Wait(150) end
    SendNUIMessage({
        action = 'openCounter',
        shop   = { id = CURRENT_SHOP, label = shopLabel, isDealer = IsDealerJob() }
    })
end

OpenBossUI = function()
    if nuiOpen then return end
    nuiOpen = true

    local shop = GetShop()
    local shopLabel = shop and (shop.label or "Concession") or "Concession"

    SetNuiFocus(true, true)
    if not uiReady then Wait(150) end
    SendNUIMessage({
        action = 'openBoss',
        shop   = { id = CURRENT_SHOP, label = shopLabel, isDealer = IsDealerJob() }
    })
end

local function ShopSpawn()
    local s = GetShop()
    if s and s.catalogue and s.catalogue.spawn then
        return s.catalogue.spawn.coords, s.catalogue.spawn.heading
    end
    return Config.Catalogue and Config.Catalogue.SpawnVehicle.coords or vector3(0,0,0),
           Config.Catalogue and Config.Catalogue.SpawnVehicle.heading or 0.0
end

local function ShopPreview()
    local s = GetShop()
    if s and s.catalogue then
        local prev = s.catalogue.preview or {}
        local cam  = s.catalogue.cam or s.catalogue.camera
        return prev, cam
    end
    return { coords = Config.Preview and Config.Preview.SpawnVehicle.coords, heading=Config.Preview and Config.Preview.SpawnVehicle.heading },
           Config.Preview and Config.Preview.Cam
end

local function _filterByShop(list)
    local shop = GetShop()
    if not shop then return list or {} end
    local cats, classes = shop.AllowedCategories, shop.AllowedClasses
    if not cats and not classes then return list or {} end
    local out = {}
    for _, v in pairs(list or {}) do
        local catOk = (not cats) or cats['*'] or cats[v.category]
        local clsOk = true
        if classes then
            local classId = GetVehicleClassFromName(joaat(v.model))
            clsOk = classes[classId] == true
        end
        if catOk and clsOk then out[#out+1] = v end
    end
    return out
end

-- =========================================================
-- ===================   TARGET (PC)   =====================
-- =========================================================
CreateThread(function()
    if Config.UseMulti and Config.Shops then
        for id, s in pairs(Config.Shops) do
            if s.catalogue and s.catalogue.coords then
                exports.ox_target:addBoxZone({
                    coords   = s.catalogue.coords,
                    rotation = s.catalogue.coords.w or 0.0,
                    debug    = false,
                    id       = 'catalogue_'..id,
                    options  = {{
                        name  = 'Concess_'..id,
                        icon  = 'fa-solid fa-clipboard-list',
                        label = ('Catalogue — %s'):format(s.label or id),
                        -- visible pour tout le monde (ou mets ta propre logique)
                        onSelect = function()
                            CURRENT_SHOP = id
                            OpenCatalogUI()
                        end
                    }}
                })
            end

            if s.comptoir and s.comptoir.coords then
                exports.ox_target:addBoxZone({
                    coords   = s.comptoir.coords,
                    rotation = s.comptoir.coords.w or 0.0,
                    debug    = false,
                    id       = 'comptoir_'..id,
                    options  = { {
                        name  = 'Comptoir_'..id,
                        icon  = 'fa-solid fa-cash-register',
                        label = ('Comptoir — %s'):format(s.label or id),
                        canInteract = function()
                            return IsDealerJob()   -- ← ne s’affiche que si employé
                        end,
                        onSelect = function()
                            CURRENT_SHOP = id
                            OpenCounterUI()
                        end
                    } }
                })
            end

            if s.boss and s.boss.coords then
                exports.ox_target:addBoxZone({
                    coords   = s.boss.coords,
                    rotation = s.boss.coords.w or 0.0,
                    debug    = false,
                    id       = 'boss_'..id,
                    options  = { {
                        name  = 'Boss_'..id,
                        icon  = 'fa-solid fa-user-tie',
                        label = ('Menu patron — %s'):format(s.label or id),
                        canInteract = function()
                            return IsBossJob()     -- ← ne s’affiche que si boss
                        end,
                        onSelect = function()
                            CURRENT_SHOP = id
                            OpenBossUI()
                        end
                    } }
                })
            end
        end
    else
        exports.ox_target:addBoxZone({
            coords = Config.Catalogue.Coords,
            rotation = 60,
            debug = false,
            id = 'catalogue_single',
            options = { {
                name  = 'Ordinateur',
                icon  = 'fa-solid fa-clipboard-list',
                label = 'Catalogue véhicules',
                onSelect = function()
                    CURRENT_SHOP = nil
                    OpenCatalogUI()
                end
            } }
        })
    end
end)

-- ======== COMPTOIR NUI <-> Client ========

RegisterNUICallback('counter:getData', function(_, cb)
  local res = lib.callback.await('ledjo:concess_money', false)
  local balance = (res and res[1] and (res[1].money or 0)) or 0
  local s = GetShop()
  local mult = (s and s.comptoir and s.comptoir.restockMultiplicateur) or 0.3
  cb({ balance = balance, restockMult = mult })
end)

RegisterNUICallback('counter:deposit', function(data, cb)
    -- data.amount
    local res = lib.callback.await('ledjo:concess_money', false)
    local base = (res and res[1] and (res[1].money or 0)) or 0
    TriggerServerEvent('ledjo:add_money_society_concess', base, tonumber(data.amount or 0))
    cb(1)
end)

RegisterNUICallback('counter:withdraw', function(data, cb)
    local res = lib.callback.await('ledjo:concess_money', false)
    local base = (res and res[1] and (res[1].money or 0)) or 0
    TriggerServerEvent('ledjo:remove_money_society_concess', base, tonumber(data.amount or 0))
    cb(1)
end)

-- Annonces
RegisterNUICallback('counter:announce', function(data, cb)
    local t = tostring(data.type or 'open')
    if t == 'open' then
        TriggerServerEvent('ledjo_concess:AnnonceOuverture')
    elseif t == 'close' then
        TriggerServerEvent('ledjo_concess:AnnonceFermeture')
    elseif t == 'custom' then
        TriggerServerEvent('ledjo_concess:AnnoncePerso', tostring(data.text or ''))
    end
    cb(1)
end)

-- Donne les clés (qs-vehiclekeys -> qb-vehiclekeys -> fallback)
local function giveKeys(plate, modelName, entity)
    -- QS VehicleKeys
    local ok = false
    local success, ret = pcall(function()
        if exports['qs-vehiclekeys'] then
            return exports['qs-vehiclekeys']:GiveKeys(plate, modelName or '', true)
        end
    end)
    ok = success and (ret ~= false)

    -- QB VehicleKeys (client event)
    if (not ok) and entity then
        local p = plate or (GetVehicleNumberPlateText(entity) or '')
        if p ~= '' then
            TriggerEvent('vehiclekeys:client:SetOwner', p)
            ok = true
        end
    end

    -- Fallback: pas de ressource de clés -> ouvrir le véhicule
    if not ok and entity and DoesEntityExist(entity) then
        SetVehicleDoorsLocked(entity, 1)
    end
    return ok
end

-- Mission de récup (repo)
RegisterNUICallback('counter:startRepo', function(data, cb)
    print('[NUI] counter:startRepo ->', json.encode(data or {}))
    lib.notify({title='[DEBUG] Repo', description='NUI counter:startRepo reçu', type='inform'})
    local model = (data and data.model) or 'blista'
    local count = tonumber(data and data.count) or 1
    if count > 5 then count = 5 end
    TriggerEvent('concess:repo:startClient', { model = model, count = count })
    cb(1)
end)

-- ======== BOSS NUI <-> Client ========

RegisterNUICallback('boss:getData', function(_, cb)
    local salaries = lib.callback.await('ledjo:concess_salaire_table', false) or {}
    local employed = lib.callback.await('ledjo:concess_employed', false) or {}
    local money    = lib.callback.await('ledjo:concess_money', false) or {}
    cb({salaries = salaries, employees = employed, balance=(money[1] and money[1].money) or 0})
end)

RegisterNUICallback('boss:setSalary', function(data, cb)
    -- data.amount, data.grade
    TriggerServerEvent('ledjo:concess_change_salaire', tonumber(data.amount or 0), data.grade)
    cb(1)
end)

RegisterNUICallback('boss:recruit', function(data, cb)
    TriggerServerEvent('ledjo:concess_recruit', tonumber(data.playerId))
    cb(1)
end)

RegisterNUICallback('boss:changeGrade', function(data, cb)
    TriggerServerEvent('ledjo:concess_modify_grade', tonumber(data.newGrade), data.identifier)
    cb(1)
end)

RegisterNUICallback('boss:fire', function(data, cb)
    TriggerServerEvent('ledjo:concess_delete_grade', data.identifier)
    cb(1)
end)


-- Liste des véhicules autorisés pour un type de slot (car|bike)
RegisterNUICallback('counter:listVehicles', function(data, cb)
    local kind = tostring(data.kind or 'car')  -- 'car' | 'bike'
    -- 1) Récupère tous les véhicules puis filtre par shop (AllowedCategories / AllowedClasses)
    local all = lib.callback.await('ledjo:concess_liste_veh', false) or {}
    all = _filterByShop(all)

    local out = {}
    for _, v in ipairs(all) do
        local classId = GetVehicleClassFromName(joaat(v.model))
        local isBike  = (classId == 8)
        local isCar   = CAR_CLASSES[classId] == true
        local ok = (kind == 'bike' and isBike) or (kind == 'car' and isCar)
        if ok then
            out[#out+1] = {
                model    = v.model,
                label    = v.name or v.model,
                category = v.category or '',
                class    = classId
            }
        end
    end

    table.sort(out, function(a,b) return (a.label or a.model) < (b.label or b.model) end)
    cb({ vehicles = out })
end)



-- Toujours la même table d’état
local ShopSpotsState = ShopSpotsState or {}
local SpotEntities    = SpotEntities or {}   

local function deleteVehEntity(ent)
    if not ent or not DoesEntityExist(ent) then return true end
    local tries = 0
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and tries < 50 do
        Wait(10)
        NetworkRequestControlOfEntity(ent)
        tries = tries + 1
    end
    SetEntityAsMissionEntity(ent, true, true)
    DeleteVehicle(ent)
    if DoesEntityExist(ent) then DeleteEntity(ent) end
    return not DoesEntityExist(ent)
end

-- fallback: si on n’a plus la handle, on cherche un véhicule proche, optionnellement par plaque
local function findVehicleByPlateNear(plate, pos, radius)
    radius = radius or 8.0
    local handle, veh = FindFirstVehicle()
    local ok = true
    while ok do
        if veh ~= 0 and DoesEntityExist(veh) then
            if #(GetEntityCoords(veh) - pos) <= radius then
                local p = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+','')
                if (plate or '') == '' or p == (plate or ''):gsub('%s+','') then
                    EndFindVehicle(handle)
                    return veh
                end
            end
        end
        ok, veh = FindNextVehicle(handle)
    end
    EndFindVehicle(handle)
    return 0
end



-- Retourne les spots du shop courant (gère spots/slots + type/kind + name/label)
local function getShopSpots()
  local s = GetShop() or {}
  local list = s.spots or s.slots or {}
  return (CURRENT_SHOP or 'default'), list
end

-- Ce que l’UI lit
local function buildSpotListForUI()
  local shop = GetShop()
  if not shop then return {} end

  local list   = shop.spots or shop.slots or {}
  local shopId = CURRENT_SHOP or 'default'
  local st     = ShopSpotsState[shopId] or {}
  local out    = {}

  for i, slot in ipairs(list) do
    local s = st[i] or { status='free' }

    -- Reconstruire vehicle à partir de model/plate si absent
    local veh = s.vehicle
    if (not veh) and (s.model or s.plate) then
      veh = { model = s.model, label = prettyLabelFor(s.model), plate = s.plate }
    end

    out[#out+1] = {
      id      = slot.id or i,
      name    = slot.name or slot.label or ('Spot '..(slot.id or i)),
      kind    = slot.type or slot.kind or 'car', -- car/bike
      status  = s.status or 'free',
      vehicle = veh
    }
  end
  return out
end

-- NUI: demander la liste
RegisterNUICallback('counter:getSpots', function(_, cb)
  cb({ spots = buildSpotListForUI() })
end)

-- NUI: assigner modèle/plaque à un spot
RegisterNUICallback('counter:spotAssign', function(data, cb)
  local shopId, spots = getShopSpots()
  local spotId = tonumber(data.spotId)
  if not spots[spotId] then cb(0) return end

  ShopSpotsState[shopId] = ShopSpotsState[shopId] or {}
  ShopSpotsState[shopId][spotId] = ShopSpotsState[shopId][spotId] or { status='free' }
  local st = ShopSpotsState[shopId][spotId]

  st.model = tostring(data.model or '')
  st.plate = tostring(data.plate or '')
  st.vehicle = (st.model ~= '' and {
    model = st.model,
    label = prettyLabelFor(st.model),
    plate = st.plate
  }) or nil

  cb(1)
end)

-- ====== Véhicules d'exposition (inutilisables) ======
local ExpoVeh = {}

local function markExpo(veh)
    if not veh or veh == 0 then return end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleDoorsLocked(veh, 2)                 -- verrou
    if SetVehicleDoorsLockedForAllPlayers then
        SetVehicleDoorsLockedForAllPlayers(veh, true)
    end
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetEntityCanBeDamaged(veh, false)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleDoorsShut(veh, true)
    ExpoVeh[veh] = true
end

local function unmarkExpo(veh)
    if not veh or veh == 0 then return end
    if SetVehicleDoorsLockedForAllPlayers then
        SetVehicleDoorsLockedForAllPlayers(veh, false)
    end
    FreezeEntityPosition(veh, false)
    SetEntityInvincible(veh, false)
    SetEntityCanBeDamaged(veh, true)
    SetVehicleUndriveable(veh, false)
    ExpoVeh[veh] = nil
end

-- Empêche d’entrer / éjecte si quelqu’un arrive à s’asseoir
CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local trying = GetVehiclePedIsTryingToEnter(ped)
        if trying ~= 0 and ExpoVeh[trying] then
            ClearPedTasksImmediately(ped)
        end
        if IsPedInAnyVehicle(ped, false) then
            local v = GetVehiclePedIsIn(ped, false)
            if ExpoVeh[v] then
                TaskLeaveVehicle(ped, v, 16)
            end
        end
    end
end)


RegisterNUICallback('counter:spotSpawn', function(data, cb)
    local shopId, spots = getShopSpots()
    local spotId = tonumber(data.spotId)
    local sp = spots[spotId]
    if not sp then cb(0) return end

    ShopSpotsState[shopId] = ShopSpotsState[shopId] or {}
    local st = ShopSpotsState[shopId][spotId] or {}
    if not st.model or st.model == '' then
        lib.notify({title='Aucun modèle', description='Assignez un modèle à ce spot avant de spawn.', type='error'})
        cb(0) return
    end

    -- supprime l’ancien véhicule du spot s’il existe
    SpotEntities[shopId] = SpotEntities[shopId] or {}
    if SpotEntities[shopId][spotId] and DoesEntityExist(SpotEntities[shopId][spotId]) then
        -- >>> enlève le statut expo avant de supprimer
        unmarkExpo(SpotEntities[shopId][spotId])
        deleteVehEntity(SpotEntities[shopId][spotId])
        SpotEntities[shopId][spotId] = nil
    end

    -- vérif type
    if not isModelAllowedForSpot({ type = sp.type or sp.kind }, st.model) then
        lib.notify({title='Spot incompatible', description='Ce slot n’accepte pas ce type de véhicule.', type='error'})
        cb(0) return
    end

    -- spawn
    local hash = (type(st.model)=='number' and st.model) or joaat(st.model)
    RequestModel(hash) while not HasModelLoaded(hash) do Wait(10) end
    local v = CreateVehicle(hash, sp.coords.x, sp.coords.y, sp.coords.z, sp.coords.w, true, true)
    SetVehicleOnGroundProperly(v)
    if st.plate and st.plate ~= '' then SetVehicleNumberPlateText(v, st.plate) end

    -- >>> rendre le véhicule de spot inutilisable
    markExpo(v)

    SpotEntities[shopId][spotId] = v
    ShopSpotsState[shopId][spotId] = st
    st.status  = 'occupied'
    st.vehicle = st.vehicle or { model = st.model, label = prettyLabelFor(st.model), plate = st.plate }
    cb(1)
end)



-- NUI: retirer (clear)
RegisterNUICallback('counter:spotClear', function(data, cb)
    local shopId, spots = getShopSpots()
    local spotId = tonumber(data.spotId)
    local sp = spots[spotId]
    ShopSpotsState[shopId] = ShopSpotsState[shopId] or {}
    local st = ShopSpotsState[shopId][spotId] or {}

    local ent = SpotEntities[shopId] and SpotEntities[shopId][spotId] or 0
    if (not ent or not DoesEntityExist(ent)) and sp and sp.coords then
        ent = findVehicleByPlateNear(st.plate or '', vec3(sp.coords.x, sp.coords.y, sp.coords.z), sp.radius or 8.0)
    end

    if ent and ent ~= 0 and DoesEntityExist(ent) then
        unmarkExpo(ent)
        deleteVehEntity(ent)
    end
    if SpotEntities[shopId] then SpotEntities[shopId][spotId] = nil end

    st.status  = 'free'
    st.vehicle = nil
    ShopSpotsState[shopId][spotId] = st

    cb(1)
end)


-- NUI: (dé)réserver
RegisterNUICallback('counter:spotReserve', function(data, cb)
  local shopId = CURRENT_SHOP or 'default'
  local spotId = tonumber(data.spotId)
  local want   = (data.reserved ~= false)
  ShopSpotsState[shopId] = ShopSpotsState[shopId] or {}
  ShopSpotsState[shopId][spotId] = ShopSpotsState[shopId][spotId] or {}
  ShopSpotsState[shopId][spotId].status = want and 'reserved' or 'free'
  cb(1)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, byShop in pairs(SpotEntities or {}) do
        for _, ent in pairs(byShop) do
            if ent and DoesEntityExist(ent) then deleteVehEntity(ent) end
        end
    end
end)


-- ====== LOGISTIQUE (client -> server) ======
RegisterNUICallback('logi:getStock', function(data, cb)
    local shopId = data and data.shopId or CURRENT_SHOP
    local shop   = (Config.Shops or {})[shopId or ''] or {}
    local mult   = (shop.comptoir and shop.comptoir.restockMultiplicateur) or 0.3
    local rows = lib.callback.await('concess:stock:list', false) or {}
    rows = _filterByShop(rows)  -- respecte les AllowedCategories/Classes du shop courant
    cb({ rows = rows, mult = mult })
end)

RegisterNUICallback('logi:order', function(data, cb)
    local model = tostring(data.model or '')
    local qty   = tonumber(data.qty or 1) or 1
    local shopId= data and data.shopId or CURRENT_SHOP
    if model=='' or qty<=0 then cb({ok=false,msg='Paramètres invalides'}) return end
    TriggerServerEvent('concess:stock:order', model, qty, shopId)
    cb({ok=true})
end)

RegisterNUICallback('logi:getHaulers', function(data, cb)
    local shop = GetShop()
    local haulers = (shop and shop.livraison and shop.livraison.haulers) or {'mule3','benson','packer'}
    local trailers = (shop and shop.livraison and shop.livraison.trailers) or {'trflat','trailersmall','trailers'}
    local outV, outT = {}, {}
    for _,m in ipairs(haulers) do outV[#outV+1] = { model = m, label = prettyLabelFor(m) } end
    for _,m in ipairs(trailers) do outT[#outT+1] = { model = m, label = prettyLabelFor(m) } end
    cb({ vehicles = outV, trailers = outT })
end)

RegisterNUICallback('logi:spawnHauler', function(data, cb)
    local ok = DoSpawnHauler(tostring(data.vehicle or 'mule3'), tostring(data.trailer or ''))
    cb({ok=ok})
end)

RegisterNUICallback('logi:clearHauler', function(_, cb)
    DoClearHauler()
    cb(1)
end)


-- === PNJ Réception (menu étendu) ===
local receptionPeds = {}

CreateThread(function()
  for id, s in pairs(Config.Shops or {}) do
    local gp = s.garagePed
    if gp and gp.model and gp.coords then
      local hash = joaat(gp.model)
      RequestModel(hash) while not HasModelLoaded(hash) do Wait(10) end
      local ped = CreatePed(4, hash, gp.coords.x, gp.coords.y, gp.coords.z, s.garagePed.heading or 0.0, false, true)
      SetEntityInvincible(ped, true)
      SetBlockingOfNonTemporaryEvents(ped, true)
      FreezeEntityPosition(ped, true)
      receptionPeds[#receptionPeds+1] = ped

      exports.ox_target:addLocalEntity(ped, {
        -- {
        --   name  = 'concess_reception_'..id,
        --   icon  = 'fa-solid fa-truck-ramp-box',
        --   label = 'Réception & Logistique (UI)',
        --   onSelect = function()
        --     CURRENT_SHOP = id
        --     COUNTER_START_SECTION = 'logi'
        --     OpenCounterUI()
        --   end
        -- },
        {
        name  = 'concess_livraison_'..id,
        icon  = 'fa-solid fa-route',
        label = 'Lancer une livraison',
        onSelect = function()
            if not IsDealerJob() then
            lib.notify({title='Logistique', description='Accès réservé au personnel.', type='error'})
            return
            end
            CURRENT_SHOP = id

            local all = lib.callback.await('ledjo:concess_liste_veh', false) or {}
            all = _filterByShop(all)
            if #all == 0 then
            lib.notify({title='Livraison', description='Aucun modèle disponible ici.', type='error'})
            return
            end

            local model = selectFrom(all, 'Modèle à réassort', 'Choisir un modèle')
            if not model then return end
            local qty = promptQty(1); if not qty then return end

            -- démarre comme la commande /repotest (spawn côté client)
            TriggerEvent('concess:repo:startClient', { model = model, count = qty })
            lib.notify({title='Livraison', description='Mission lancée', type='inform'})
        end
        },
        -- {
        --   name  = 'concess_restock_'..id,
        --   icon  = 'fa-solid fa-boxes-packing',
        --   label = 'Réassort direct (+stock)',
        --   onSelect = function()
        --     if not IsDealerJob() then
        --       lib.notify({title='Logistique', description='Accès réservé au personnel.', type='error'}); return
        --     end
        --     CURRENT_SHOP = id
        --     local all = lib.callback.await('ledjo:concess_liste_veh', false) or {}
        --     all = _filterByShop(all)
        --     if #all == 0 then
        --       lib.notify({title='Réassort', description='Aucun modèle disponible ici.', type='error'}); return
        --     end
        --     local model = selectFrom(all, 'Modèle à réassort', 'Choisir un modèle')
        --     if not model then return end
        --     local qty = promptQty(1); if not qty then return end
        --     local shop = (Config.Shops or {})[CURRENT_SHOP or id] or {}
        --     local mult = (shop.comptoir and shop.comptoir.restockMultiplicateur) or 0.3
        --     TriggerServerEvent('ledjo:concess_restock', CURRENT_SHOP or id, model, qty, mult)
        --   end
        -- },
        {
          name  = 'concess_haul_spawn_'..id,
          icon  = 'fa-solid fa-truck-moving',
          label = 'Spawner utilitaire (camion + remorque)',
          onSelect = function()
            if not IsDealerJob() then
              lib.notify({title='Logistique', description='Accès réservé au personnel.', type='error'}); return
            end
            CURRENT_SHOP = id
            local shop = GetShop()
            local haulers  = (shop and shop.livraison and shop.livraison.haulers)  or {'flatbed','phantom3'}
            local trailers = (shop and shop.livraison and shop.livraison.trailers) or {'tr2'}

            -- options lisibles
            local hv = {}; for _,m in ipairs(haulers)  do hv[#hv+1] = {model=m, label=prettyLabelFor(m)} end
            local tv = {}; for _,m in ipairs(trailers) do tv[#tv+1] = {model=m, label=prettyLabelFor(m)} end

            local v  = selectFrom(hv, 'Utilitaire', 'flatbed/phantom3…'); if not v then return end
            local t  = lib.inputDialog('Remorque (optionnelle)', { {type='select', label='Remorque', options=(function()
                  local o={{value='',label='(Aucune)'}}
                  for _,x in ipairs(tv) do o[#o+1]={value=x.model,label=x.label} end
                  return o
            end)()} })
            local trailer = (t and t[1] ~= '') and t[1] or ''
            local ok = DoSpawnHauler(v, trailer)
            if not ok then lib.notify({title='Utilitaire', description='Spawn impossible.', type='error'}) end
          end
        },
        {
          name  = 'concess_haul_clear_'..id,
          icon  = 'fa-solid fa-warehouse',
          label = 'Ranger utilitaire',
          onSelect = function()
            CURRENT_SHOP = id
            DoClearHauler()
            lib.notify({title='Utilitaire', description='Attelage rangé.', type='success'})
          end
        }
      })
    end
  end
end)


-- Modifie OpenCounterUI pour passer la section de départ à l’UI
local COUNTER_START_SECTION = nil
OpenCounterUI = function()
    if nuiOpen then return end
    nuiOpen = true

    local shop = GetShop()
    local shopLabel = shop and (shop.label or "Concession") or "Concession"

    SetNuiFocus(true, true)
    if not uiReady then Wait(150) end
    SendNUIMessage({
        action = 'openCounter',
        shop   = { id = CURRENT_SHOP, label = shopLabel, isDealer = IsDealerJob() },
        startSection = COUNTER_START_SECTION or 'spots'
    })
    COUNTER_START_SECTION = nil
end

-- Liste stock (pour la vue en lignes)
RegisterNUICallback('stock:getList', function(data, cb)
    local rows = lib.callback.await('concess:stock:list', false) or {}
    cb({ rows = rows })
end)


-- Vente "papier" (facture) → le serveur demandera l'accord au client ciblé
RegisterNUICallback('stock:sellToClient', function(data, cb)
    local target = tonumber(data and data.targetId)
    if not target then cb({ok=false}) return end
    local payload = { model = tostring(data.model), name = tostring(data.name or data.model), price = tonumber(data.price or 0), shopId = CURRENT_SHOP }
    TriggerServerEvent('concess:sell:requestPay', target, payload)
    cb({ok=true})
end)

-- Le serveur propose une facture au client (acheteur)
RegisterNetEvent('concess:sell:bill', function(token, sellerId, payload)
    local txt = ('Acheter %s pour %s$ ?'):format(payload.name or payload.model, payload.price or 0)
    local input = lib.inputDialog('Facture concession', {
        {type='select', label='Moyen de paiement', options={{
            value='bank', label='Banque'
        },{ value='money', label='Liquide' }}, default='bank', required=true}
    })
    local accepted, pay = false, 'bank'
    if input and input[1] then accepted, pay = true, tostring(input[1]) end
    TriggerServerEvent('concess:sell:answer', token, accepted, pay)
end)


-- Paiement accepté → pousser cela à l'UI (qui appellera ui:buyAsDealer avec targetId)
RegisterNetEvent('concess:sell:paid', function(payload)
    SendNUIMessage({ action='stock:paid', targetId = payload.targetId, model = payload.model, name = payload.name, price = payload.price, pay = payload.pay })
end)

-- Refus (optionnel)
RegisterNetEvent('concess:sell:denied', function(reason)
    lib.notify({ title='Vente', description= reason or 'Facture refusée', type='error' })
end)

-- (facultatif) ui:buyAsDealer peut accepter targetId si fourni
-- Dans ton NUI callback 'ui:buyAsDealer', remplace la recherche du joueur proche par :
-- local target = data.targetId or (near[1] and near[1].id)











-- ===== LOGISTIQUE =====
RegisterNUICallback('logi:listVehicles', function(_, cb)
  local all = lib.callback.await('ledjo:concess_liste_veh', false) or {}
  all = _filterByShop(all)  -- respecte AllowedCategories/Classes du shop courant
  cb({ vehicles = all })
end)

-- Livraison "camion" (mission) – version simple
StartLivraison = function(model, qty, mult)
    local L = getLivraison()
    if not L or not L.pickup or not L.depot then
        lib.notify({title='Logistique', description='Shop non configuré (pickup/depot).', type='error'})
        return
    end
    qty  = tonumber(qty) or 1
    local shop = GetShop()
    mult = tonumber(mult) or (shop and shop.comptoir and shop.comptoir.restockMultiplicateur) or 0.3

    -- validation modèle
    local list = lib.callback.await('ledjo:concess_liste_veh', false) or {}
    local found; for _,r in ipairs(list) do if r.model==model or r.name==model then found=r break end end
    if not found then
        lib.notify({title='Logistique', description='Modèle introuvable.', type='error'}); return
    end

    -- camion simple (tu peux aussi réutiliser DoSpawnHauler si tu veux l’attelage ici)
    local mhash = joaat('flatbed')
    RequestModel(mhash) while not HasModelLoaded(mhash) do Wait(10) end
    local st = L.spawnTruck or L.depot or L.pickup
    local truck = CreateVehicle(mhash, st.x, st.y, st.z, st.w or 0.0, true, true)
    ensurePlacedOnGround(truck)
    SetPedIntoVehicle(PlayerPedId(), truck, -1)

    -- étape 1 : aller au pickup
    local blip = AddBlipForCoord(L.pickup.x, L.pickup.y, L.pickup.z)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Point de chargement'); EndTextCommandSetBlipName(blip)
    lib.notify({title='Livraison', description='Allez au point de chargement.', type='inform'})

    local stage = 1
    CreateThread(function()
        while DoesEntityExist(truck) do
            Wait(400)
            local p = GetEntityCoords(truck)
            if stage == 1 then
                if #(p - vec3(L.pickup.x, L.pickup.y, L.pickup.z)) < 8.0 then
                    if blip then RemoveBlip(blip) blip=nil end
                    blip = AddBlipForCoord(L.depot.x, L.depot.y, L.depot.z)
                    SetBlipRoute(blip, true)
                    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Livrer au dépôt'); EndTextCommandSetBlipName(blip)
                    lib.notify({title='Livraison', description='Chargement effectué, livrez au dépôt.', type='inform'})
                    stage = 2
                end
            elseif stage == 2 then
                if #(p - vec3(L.depot.x, L.depot.y, L.depot.z)) < 8.0 then
                    if blip then RemoveBlip(blip) blip=nil end
                    TriggerServerEvent('ledjo:concess_restock', CURRENT_SHOP or 'auto', model, qty, mult)
                    lib.notify({title='Livraison', description='Réappro effectué.', type='success'})
                    DeleteEntity(truck)
                    break
                end
            end
        end
    end)
end


RegisterNUICallback('logi:startLivraison', function(data, cb)
  StartLivraison(tostring(data.model), tonumber(data.qty) or 1, tonumber(data.mult))
  cb(1)
end)

RegisterNUICallback('logi:restockDirect', function(data, cb)
  TriggerServerEvent('ledjo:concess_restock', CURRENT_SHOP or 'auto', tostring(data.model), tonumber(data.qty) or 1, tonumber(data.mult))
  cb(1)
end)

-- ===== HISTORIQUE =====
RegisterNUICallback('counter:getHistory', function(_, cb)
  local rows = lib.callback.await('ledjo:concess_historique', false) or {}
  cb({ history = rows })
end)

RegisterNUICallback('counter:deleteHistory', function(data, cb)
  TriggerServerEvent('ledjo:concess_delete_historique', tonumber(data.id))
  cb(1)
end)


-- =========================================================
-- ======================   N U I   ========================
-- =========================================================
local function rgbFromHex(hex)
    if not hex then return 0,0,0 end
    hex = hex:gsub("#","")
    if #hex == 3 then
        return tonumber("0x"..hex:sub(1,1)..hex:sub(1,1)) or 0,
               tonumber("0x"..hex:sub(2,2)..hex:sub(2,2)) or 0,
               tonumber("0x"..hex:sub(3,3)..hex:sub(3,3)) or 0
    end
    return tonumber("0x"..hex:sub(1,2)) or 0,
           tonumber("0x"..hex:sub(3,4)) or 0,
           tonumber("0x"..hex:sub(5,6)) or 0
end

local function openCam()
    local _, camCfg = ShopPreview()
    if not camCfg then return end
    previewCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(previewCam, camCfg.coords)
    SetCamRot(previewCam, -0.0, 0.0, camCfg.heading)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, false, 0, true, true)
    TaskStartScenarioInPlace(PlayerPedId(),'WORLD_HUMAN_CLIPBOARD', 0, true)
    FreezeEntityPosition(PlayerPedId(), true)
end

local function closeCam()
    if previewCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
    FreezeEntityPosition(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
end

local function destroyPreview()
    if previewVeh and DoesEntityExist(previewVeh) then
        DeleteEntity(previewVeh)
        previewVeh = nil
    end
end

function OpenCatalogUI()
    if nuiOpen then return end
    nuiOpen = true

    local shop = GetShop()
    local shopLabel = shop and (shop.label or "Concession") or "Concession"

    -- catégories
    lib.callback('ledjo:concess_liste_cat', false, function(result)
        local allowCat = shop and shop.AllowedCategories or nil
        local cats = {}
        for _,v in pairs(result or {}) do
            if (not allowCat) or allowCat['*'] or allowCat[v.name] then
                cats[#cats+1] = { name=v.name, label=v.label, image=v.image }
            end
        end

        SetNuiFocus(true, true)
        if not uiReady then Wait(150) end
            SendNUIMessage({
                action = 'open',
                shop   = {
                    id        = CURRENT_SHOP,
                    label     = shopLabel,
                    isDealer  = IsDealerJob(),
                    dealersOnline = staffCount or 0
                },
                categories = cats
            })
        openCam()
    end)
end

local function CloseUI()
    if not nuiOpen then return end
    nuiOpen = false
    destroyPreview()
    closeCam()
    SetNuiFocus(false, false)
    SendNUIMessage({action='close'})
end

RegisterNUICallback('ui:close', function(_,cb)
    CloseUI()
    cb(1)
end)

RegisterNUICallback('ui:getVehicles', function(data, cb)
    local cat = data and data.category
    lib.callback('ledjo:concess_liste_veh_from_cat', false, function(result)
        result = _filterByShop(result)
        local items = {}
        for _,v in pairs(result or {}) do
            if v.category == cat then
                local mdl = joaat(v.model)
                items[#items+1] = {
                    name  = v.name,
                    label = v.name,
                    model = v.model,
                    image = v.image,
                    price = v.price,
                    category = v.category,
                    stock = v.stock,
                    stats = {
                        vmax = math.floor(GetVehicleModelEstimatedMaxSpeed(mdl)*3.6),
                        seats = GetVehicleModelNumberOfSeats(mdl),
                        accel = math.floor(GetVehicleModelAcceleration(mdl)*100),
                        brake = math.floor(GetVehicleModelMaxBraking(mdl)*100),
                    }
                }
            end
        end
        cb({vehicles = items})
    end, cat)
end)


-- === Blips multi-shops ===
CreateThread(function()
    if not (Config.Shops and next(Config.Shops)) then return end

    for id, s in pairs(Config.Shops) do
        local b = s.blip
        if b and b.pos then
            local x, y, z = b.pos.x or b.pos[1], b.pos.y or b.pos[2], b.pos.z or b.pos[3]
            local blip = AddBlipForCoord(x, y, z)
            SetBlipSprite(blip, b.type or 523)
            SetBlipScale(blip,  b.size or 0.8)
            SetBlipColour(blip, b.color or 0)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(b.title or s.label or ('Concession: %s'):format(id))
            EndTextCommandSetBlipName(blip)
        end
    end
end)

RegisterNUICallback('ui:preview', function(data, cb)
    destroyPreview()
    local prev, _ = ShopPreview()
    local coords = prev and prev.coords or (Config.Preview and Config.Preview.SpawnVehicle.coords) or GetEntityCoords(PlayerPedId())
    local heading = prev and prev.heading or (Config.Preview and Config.Preview.SpawnVehicle.heading) or 0.0

    local model = (type(data.model)=='string' and joaat(data.model)) or data.model
    RequestModel(model); while not HasModelLoaded(model) do Wait(10) end
    previewVeh = CreateVehicle(model, coords.x, coords.y, coords.z, heading, false, false)
    SetVehicleNumberPlateText(previewVeh, "CONCESS")
    SetVehicleOnGroundProperly(previewVeh)
    FreezeEntityPosition(previewVeh, true)
    cb(1)
end)

RegisterNUICallback('ui:recolor', function(data, cb)
    if not previewVeh then cb(0); return end
    local r,g,b = rgbFromHex(data.primary)
    local r2,g2,b2 = rgbFromHex(data.secondary)
    SetVehicleCustomPrimaryColour(previewVeh, r,g,b)
    SetVehicleCustomSecondaryColour(previewVeh, r2,g2,b2)
    cb(1)
end)
RegisterNUICallback('ui:ready', function(_, cb)
    uiReady = true
    cb(1)
end)
-- util
local function randomPlate()
    local plate = lib.callback.await('concess:plate:alloc', false)
    if plate and type(plate) == 'string' then
        return plate
    end
    -- Fallback local si le serveur ne répond pas
    local letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local l = letters:sub(math.random(26), math.random(26)) .. letters:sub(math.random(26), math.random(26)) .. letters:sub(math.random(26), math.random(26))
    local n = string.format('%04d', math.random(0, 9999))
    return (l .. ' ' .. n)
end


local function getNearbyPlayers(maxDist)
    local me = PlayerId()
    local myPed = PlayerPedId()
    local myPos = GetEntityCoords(myPed)
    local out = {}
    for _,pid in ipairs(GetActivePlayers()) do
        if pid ~= me then
            local ped = GetPlayerPed(pid)
            local dist = #(GetEntityCoords(ped)-myPos)
            if dist <= (maxDist or 10.0) then
                out[#out+1] = { id = GetPlayerServerId(pid), name = GetPlayerName(pid), distance = math.floor(dist) }
            end
        end
    end
    table.sort(out, function(a,b) return a.distance < b.distance end)
    return out
end


-- NUI: facture via export vms_cityhall (ouverture d’une facture vide)
RegisterNUICallback('stock:bill', function(data, cb)
    -- 1) Vérifier qu’il y a bien un client à proximité (8m)
    local near = getNearbyPlayers(8.0)
    if #near == 0 then
        if lib and lib.notify then
            lib.notify({title='Facture', description='Aucun client proche.', type='error'})
        end
        cb({ ok = false, msg = 'Aucun client proche.' })
        return
    end

    -- 2) Vérifier que le script facture est bien démarré
    if not GetResourceState or GetResourceState('vms_cityhall') ~= 'started' then
        if lib and lib.notify then
            lib.notify({title='Facture', description='vms_cityhall non démarré.', type='error'})
        end
        cb({ ok = false, msg = 'vms_cityhall non démarré.' })
        return
    end

    -- 3) Ouvrir l’UI de facture (vide) côté vms_cityhall
    local ok, err = pcall(function()
        exports['vms_cityhall']:openEmptyInvoice()
    end)
    if not ok then
        if lib and lib.notify then
            lib.notify({title='Facture', description='Export facture indisponible.', type='error'})
        end
        cb({ ok = false, msg = tostring(err or 'export_failed') })
        return
    end

    -- 4) Fermer ton menu Concession immédiatement (comme demandé)
    if CloseUI then
        CloseUI()
    else
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
    end

    if lib and lib.notify then
        lib.notify({title='Facture', description='Facture ouverte (remplissez-la).', type='success'})
    end
    cb({ ok = true })
end)


RegisterNUICallback('ui:getNearby', function(data, cb)
    cb({players = getNearbyPlayers(data and data.max or 10.0)})
end)

-- Achat perso (mode auto)
RegisterNUICallback('ui:buySelf', function(data, cb)
    local shop = GetShop()
    local spawnCoords, spawnHeading = ShopSpawn()
    local model = data.model
    local plate = randomPlate()
    local r,g,b = rgbFromHex(data.color)

    lib.callback('ledjo:concess_verif_money', false, function(ok)
        if not ok then cb({ok=false, msg='Argent insuffisant'}); return end
        ESX.Game.SpawnVehicle(model, spawnCoords, spawnHeading, function(vehicle)
            SetVehicleNumberPlateText(vehicle, plate)
            SetVehicleCustomPrimaryColour(vehicle, r,g,b)
            local props = lib.getVehicleProperties(vehicle)
            SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
            TriggerServerEvent('ledjo:concess_buy_car', data.name, data.price, props, plate, data.stock or 1, ('rgb(%d,%d,%d)'):format(r,g,b), data.pay)
            TriggerServerEvent('ledjo:concess_add_historique', "Vente", "/", data.price, data.name)
            if exports['qs-vehiclekeys'] then
                exports['qs-vehiclekeys']:GiveKeys(plate, model, true)
            end
        end)
        cb({ok=true})
    end, data.price, data.pay)
end)

-- Achat vendeur (particulier/moi/entreprise)
RegisterNUICallback('ui:buyAsDealer', function(data, cb)
    if not IsDealerJob() then cb({ok=false, msg='Réservé au personnel'}); return end

    local typ = data.customerType -- 'particulier' | 'moi' | 'entreprise'
    local model = data.model
    local plate = randomPlate()
    local r,g,b = rgbFromHex(data.color)
    local spawnCoords, spawnHeading = ShopSpawn()

    if typ == 'particulier' then
      local target = tonumber(data.targetId) -- <- PRIORITAIRE si fourni
        if not target then
            local near = getNearbyPlayers(10.0)
            if #near == 0 then cb({ok=false, msg='Aucun client proche'}); return end
            target = near[1].id
        end
        lib.callback('ledjo:concess_verif_money_vendeur', false, function(ok)
            if not ok then cb({ok=false, msg='Le client n’a pas assez d’argent'}); return end
            ESX.Game.SpawnVehicle(model, spawnCoords, spawnHeading, function(vehicle)
                SetVehicleNumberPlateText(vehicle, plate)
                SetVehicleCustomPrimaryColour(vehicle, r,g,b)
                local props = lib.getVehicleProperties(vehicle)
                TriggerServerEvent('ledjo:concess_buy_car_vendeur', data.name, data.price, props, plate, data.stock or 1, ('rgb(%d,%d,%d)'):format(r,g,b), data.pay, target)
                TriggerServerEvent('ledjo:concess_add_historique', "Vente Automatique", "/", data.price, data.name)
                if exports['qs-vehiclekeys'] then exports['qs-vehiclekeys']:GiveKeys(plate, model, true) end
            end)
            cb({ok=true})
        end, data.price, data.pay, target)

    elseif typ == 'moi' then
        local myId = GetPlayerServerId(PlayerId())
        lib.callback('ledjo:concess_verif_money_vendeur', false, function(ok)
            if not ok then cb({ok=false, msg='Argent insuffisant'}); return end
            ESX.Game.SpawnVehicle(model, spawnCoords, spawnHeading, function(vehicle)
                SetVehicleNumberPlateText(vehicle, plate)
                SetVehicleCustomPrimaryColour(vehicle, r,g,b)
                local props = lib.getVehicleProperties(vehicle)
                SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
                TriggerServerEvent('ledjo:concess_buy_car_vendeur', data.name, data.price, props, plate, data.stock or 1, ('rgb(%d,%d,%d)'):format(r,g,b), data.pay, myId)
                TriggerServerEvent('ledjo:concess_add_historique', "Vente Automatique", "/", data.price, data.name)
                if exports['qs-vehiclekeys'] then exports['qs-vehiclekeys']:GiveKeys(plate, model, true) end
            end)
            cb({ok=true})
        end, data.price, data.pay, myId)

    elseif typ == 'entreprise' then
        local company = data.company or ''
        if company == '' then cb({ok=false, msg='Nom d’entreprise manquant'}); return end
        lib.callback('ledjo:concess_verif_money_entreprise', false, function(ok)
            if not ok then cb({ok=false, msg='Entreprise sans fonds'}); return end
            ESX.Game.SpawnVehicle(model, spawnCoords, spawnHeading, function(vehicle)
                SetVehicleNumberPlateText(vehicle, plate)
                SetVehicleCustomPrimaryColour(vehicle, r,g,b)
                local props = lib.getVehicleProperties(vehicle)
                SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
                TriggerServerEvent('ledjo:concess_buy_car_entreprise', data.name, data.price, props, plate, data.stock or 1, data.label or data.name, ('rgb(%d,%d,%d)'):format(r,g,b), company)
                TriggerServerEvent('ledjo:concess_add_historique', "Vente Automatique", "/", data.price, data.name)
                if exports['qs-vehiclekeys'] then exports['qs-vehiclekeys']:GiveKeys(plate, model, true) end
            end)
            cb({ok=true})
        end, data.price, company)
    else
        cb({ok=false, msg='Type de client invalide'})
    end
end)

-- =========================================================
-- ==================   SAFE EXIT HANDLING   ===============
-- =========================================================

-- Fermer si joueur meurt / change de job etc.
AddEventHandler('esx:onPlayerDeath', function() CloseUI() end)
RegisterNetEvent('esx:playerLoaded', function(xPlayer) ESX.PlayerData = xPlayer end)
RegisterNetEvent('esx:setJob', function(job) ESX.PlayerData.job = job end)


-- ========= REPO CLIENT =========

local repoActive = false
-- on gère maintenant plusieurs véhicules/blips
local repoVehs, repoBlips = {}, {}
local repoTarget = nil

local function clearRepo()
    for _, bl in ipairs(repoBlips) do if bl then RemoveBlip(bl) end end
    repoBlips = {}
    for _, ent in ipairs(repoVehs) do
        if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    repoVehs = {}
    repoTarget = nil
    repoActive = false
end

-- point d'arrivée = zone de stock du shop courant
local function getRepoReturnPoint()
    local s = GetShop()
    if s and s.livraison and s.livraison.stock then
        return s.livraison.stock
    end
    return vector4(0.0,0.0,0.0,0.0)
end

RegisterNetEvent('concess:repo:startClient', function(veh)
    dprint('Event concess:repo:startClient reçu, payload=', json.encode(veh or {}))
    local L = ensureCurrentShopForRepo()
    if not L or not L.pickup then
        lib.notify({title='Récupération', description='Pickup introuvable (shop non défini).', type='error'})
        dprint('getLivraison() NIL - vérifier Config.Shops[<shop>].livraison.pickup')
        return
    end

    clearRepo()
    dnotify('début event (client)')

    -- résolution modèle
    local mdl = veh and veh.model
    local h   = (type(mdl) == 'number') and mdl or joaat(tostring(mdl or 'blista'))
    if not IsModelInCdimage(h) or not IsModelAVehicle(h) then
        lib.notify({title='Récupération', description=("Modèle invalide: %s"):format(tostring(mdl)), type='error'})
        dprint('modèle invalide:', tostring(mdl))
        return
    end
    RequestModel(h) while not HasModelLoaded(h) do Wait(10) end

    local wanted = math.min(tonumber(veh and (veh.max or veh.count)) or 1, 5)
    if wanted <= 0 then wanted = 1 end

    -- *** NOUVEAU: pas de best spawn, on reste à L.pickup avec offsets <= 4.0 ***
    local base = vector4(L.pickup.x, L.pickup.y, L.pickup.z, L.pickup.w or 0.0)
    local offsets = {
        vec3(0.0, 0.0, 0.0),
        vec3(4.0, 0.0, 0.0),
        vec3(-4.0, 0.0, 0.0),
        vec3(0.0, 4.0, 0.0),
        vec3(0.0, -4.0, 0.0)
    }

    local modelName = (type(mdl) == 'string' and mdl) or (GetDisplayNameFromVehicleModel(h) or 'unknown')

    for i = 1, wanted do
        local off = offsets[i] or offsets[#offsets]
        local sx, sy, sz, sh = base.x + off.x, base.y + off.y, base.z, base.w
        local ent = CreateVehicle(h, sx, sy, sz, sh, true, true)
        if ent ~= 0 then
            SetEntityAsMissionEntity(ent, true, true)
            ensurePlacedOnGround(ent)
            SetVehicleOnGroundProperly(ent)
            SetVehicleDoorsShut(ent, true)
            SetVehicleDoorsLocked(ent, 2)

            local plate = randomPlate()
            SetVehicleNumberPlateText(ent, plate)
            local got = giveKeys(plate, modelName, ent)
            dprint(('spawn #%d @%.2f %.2f (keys=%s, plate=%s)'):format(i, sx, sy, tostring(got), plate))

            NetworkFadeInEntity(ent, true); SetEntityVisible(ent, true, 0)
            local bl = AddBlipForEntity(ent)
            SetBlipSprite(bl, 225); SetBlipColour(bl, 46)
            BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Véhicule à récupérer'); EndTextCommandSetBlipName(bl)

            repoVehs[#repoVehs+1] = ent
            repoBlips[#repoBlips+1] = bl
        else
            dprint('CreateVehicle a renvoyé 0 (échec spawn)')
        end
        Wait(50)
    end

    if #repoVehs == 0 then
        lib.notify({title='Récupération', description='Aucun véhicule n’a pu être spawné.', type='error'})
        return
    end

    repoActive = true
    dnotify(('spawn OK x%d'):format(#repoVehs))

    -- *** NOUVEAU: afficher le point de dépose dès qu'on est dans la zone du véhicule à récupérer ***
    local depositBlip = nil
    CreateThread(function()
        local ret = L.stock or L.depot or L.pickup
        local shown = false
        while repoActive and (not shown) do
            Wait(250)
            local p = GetEntityCoords(PlayerPedId())
            for _, ent in ipairs(repoVehs) do
                if ent ~= 0 and DoesEntityExist(ent) then
                    if #(p - GetEntityCoords(ent)) <= 4.0 then
                        if depositBlip then RemoveBlip(depositBlip) end
                        depositBlip = AddBlipForCoord(ret.x, ret.y, ret.z)
                        SetBlipSprite(depositBlip, 1)
                        SetBlipColour(depositBlip, 2)
                        SetBlipRoute(depositBlip, true)
                        BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Point de dépose'); EndTextCommandSetBlipName(depositBlip)
                        lib.notify({title='Livraison', description='Amenez le véhicule au point de dépose.', type='inform'})
                        shown = true
                        break
                    end
                end
            end
        end
    end)

    -- suivi retour (validation quand on amène LE véhicule dans la zone de dépôt)
    CreateThread(function()
        local ret = L.stock or L.depot or L.pickup
        local retVec = vec3(ret.x, ret.y, ret.z)
        local radius = 5.0
        while repoActive do
            Wait(400)
            local ped = PlayerPedId()
            local cur = GetVehiclePedIsIn(ped,false)
            if cur ~= 0 then
                for _, ent in ipairs(repoVehs) do
                    if ent == cur and #(GetEntityCoords(cur) - retVec) <= radius then
                        -- >>> RETIRER LES CLÉS ICI <<<
                        local plate = (GetVehicleNumberPlateText(cur) or '')
                        removeKeys(plate, cur, modelName) 

                        TriggerServerEvent('concess:repo:complete', modelName)
                        dnotify('retour effectué → complete() envoyé')

                        if depositBlip then RemoveBlip(depositBlip); depositBlip = nil end
                        clearRepo()
                        return
                    end
                end
            end
        end
    end)

    -- (optionnel) marqueur debug 10s au pickup
    local untilT = GetGameTimer() + 10000
    CreateThread(function()
        while GetGameTimer() < untilT do
            DrawMarker(1, base.x, base.y, base.z+1.0, 0,0,0, 0,0,0, 1.0,1.0,1.0, 255,255,255,120, false,true,2, false,nil,nil,false)
            Wait(0)
        end
    end)
end)
