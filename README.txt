ajoutez l'item dans ton ox_inventory/data/items.lua
['carkey'] = {
        label = 'Carkey',
        weight = 300,
        stack = false
},

Ajoutez ca dans ox_inventory/modules/items/client.lua
Item('carkey', function(data, slot)
    TriggerEvent('carkeys:client:useKey', slot)
end)

