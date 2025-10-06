fx_version 'cerulean'
game 'gta5'
lua54 'yes'
description 'Takiira_Concess'
author 'Takiira'
version '1.10.10' 


shared_scripts {
  'shared/config.lua',   -- <= d'abord !
  '@ox_lib/init.lua'
};

client_scripts {
    'client/**/**/*.lua',
}

ui_page 'web/index.html'

server_scripts {
    "@oxmysql/lib/MySQL.lua",
    'server/**/**/*.lua',
}

dependencies {
  'oxmysql',
  'ox_target'
}

files {
  'web/index.html',
  'web/style.css',
  'web/app.js'
}
