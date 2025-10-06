Config = Config or {}
Config.UseMulti = true
Config.CatalogueOnlyStaff = false
Config.LeDjo_Garage = true
Config.LockingRange = 5.0
Config.CycleVehicleClass = 13
Config.Keyitem = "carkeys"
Config.KeyPrice = 100
Config.KeyShop = {
    Ped = { Model = 'a_m_m_genfat_01', Position = vector4(10000000,10000000,0,0) }
}


Config.Shops = {
  auto = {
    label = 'Concessionnaire',
    job   = 'concess',
    jobs  = { concess = true },            -- tu peux en rajouter d’autres ici si besoin
    society = 'society_concess',           -- coffre/compte par shop

    blip = {                               -- ex-Config.Blips
      pos   = vector3(162.9105, -1106.2233, 29.1950),
      type  = 523, size = 0.7, color = 48,
      title = '~c~Concessionaire~s~ | Los Santos'
    },

    livraison = {                          -- ex-Config.Livraison
      spawn   = {
        truck   = vec4(145.20013427734, -1073.6643066406, 29.194412231445, 65.829055786133),
        trailer = vec4(147.16444396973, -1065.6219482422, 29.194404602051, 81.782386779785)
      },
      pickup  = vector4(568.91162109375, -2308.2587890625, 5.9156975746155, 11.807559967041),
      depot   = vector4(116.74174499512, -1056.2248535156, 29.194396972656, 180.09808349609),
      stock       = vector4(116.74174499512, -1056.2248535156, 29.194396972656, 180.09808349609),
	  haulers  = {'flatbed','phantom3'},
      trailers = {'tr2'}
    },

    catalogue = {                          -- ex-Config.Catalogue + Preview + spawn
      coords  = vector4(156.9762, -1108.2394, 29.1951, 111.0609),
      preview = { coords = vector3(153.2474, -1108.1558, 29.4387), heading = 303.6652 },
      spawn   = { coords = vector3(135.0231, -1094.0894, 29.1951), heading = 102.0680 },
      cam     = { enabled = true, coords = vector3(160.1710, -1106.8975, 30.1951), heading = 99.7397 },
    },

    comptoir = {                            -- ex-Config.Comptoir
      coords = vector4(162.0726, -1103.8157, 29.2115, 166.2586),
      restockMultiplicateur = 0.3
    },

    coffre = {                              -- ex-Config.Coffre
      id = 'society_concess',
      label = 'Concessionnaire',
      slots = 50,
      weight = 100000,
      coords = vector4(141.9701, -1105.2421, 29.1951, 245.7299)
    },

    boss = {                                -- ex-Config.BossMenu
      coords = vector4(144.4854, -1100.5977, 29.1951, 344.9015),
      maxSalary = 4000
    },


    AllowedCategories = {
		compacts=true, coupes=true, sedans=true, sports=true, sportsclassics=true,
		super=true, muscle=true, offroad=true, suvs=true, vans=true, motorcycles=true
	},

    AllowedClasses    = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[12]=true },


    garagePed = { model = "a_m_m_og_boss_01", coords = vec3(163.3517, -1086.6912, 28.1944), heading = 359.1566 },
    wardrobes = {
      men   = { { coords = vec3(-1164.0475, -1694.8199, 9.8995), heading = 303.0586, icon="fas fa-hand-paper", labeltarget="Vestiaires Hommes" } },
      women = { { coords = vec3(-1167.4698, -1690.2875, 9.8996), heading = 303.7232, icon="fas fa-hand-paper", labeltarget="Vestiaires Femmes" } },
    },

	spots = {
		{ id=1,  name="Spot 1",  coords=vector4(170.5093536377, -1107.9982910156, 29.437797546387, 45.165828704834),  radius=3.5, type='car'  },
		{ id=2,  name="Spot 2",  coords=vector4(169.9697265625, -1113.7781982422, 29.319402694702, 82.396606445312),  radius=3.5, type='car' },
		{ id=3,  name="Spot 3",  coords=vector4(172.30178833008, -1100.13671875, 29.438737869263, 83.414009094238),  radius=3.5, type='car'  },
		{ id=4,  name="Spot 4",  coords=vector4(181.23960876465, -1107.947265625, 29.395620346069, 81.713973999023),  radius=3.5, type='car'  },
		{ id=5,  name="Spot 5",  coords=vector4(181.27851867676, -1103.859375, 29.395626068115, 85.411315917969),  radius=3.5, type='car'  },
		{ id=6,  name="Spot 6",  coords=vector4(181.07373046875, -1100.1496582031, 29.395626068115, 88.431327819824),  radius=3.5, type='car'  },
		{ id=7,  name="Spot 7",  coords=vector4(181.32106018066, -1095.8048095703, 29.395626068115, 94.383522033691),  radius=3.5, type='car'  },
		{ id=8,  name="Spot 8",  coords=vector4(174.48526000977, -1092.4284667969, 29.398904800415, 151.29991149902),  radius=3.5, type='bike'  },
		{ id=9,  name="Spot 9",  coords=vector4(172.52217102051, -1092.4184570312, 29.398910522461, 140.40110778809),  radius=3.5, type='bike'  },
		{ id=10,  name="Spot 10",  coords=vector4(170.57183837891, -1092.5119628906, 29.398864746094, 146.66734313965),  radius=3.5, type='bike'  },
		{ id=11,  name="Spot 11",  coords=vector4(168.55087280273, -1092.521484375, 29.401563644409, 151.51063537598),  radius=3.5, type='bike'  },
		{ id=12,  name="Spot 12",  coords=vector4(166.56048583984, -1092.6812744141, 29.398946762085, 150.65789794922),  radius=3.5, type='bike'  },
		{ id=13,  name="Spot 13",  coords=vector4(152.57662963867, -1091.828125, 29.438888549805, 244.51690673828),  radius=3.5, type='car'  },
		{ id=14,  name="Spot 14",  coords=vector4(151.02186584473, -1099.8616943359, 29.4387550354, 262.86505126953),  radius=3.5, type='car'  },
		{ id=15,  name="Spot 15",  coords=vector4(154.86836242676, -1113.8557128906, 29.319404602051, 269.52932739258),  radius=3.5, type='car'  },
	}
  },
  -- roxwood -----------------------------------------------------------------------------
  roxwood = {
    label = 'Concessionnaire Roxwood',
    job   = 'concess_roxwood',
    jobs  = { concess_roxwood = true },            
    society = 'society_concess_roxwood',           

    blip = {                               -- ex-Config.Blips
      pos   = vector3(-362.40042114258, 7465.8295898438, 6.4103789329529),
      type  = 523, size = 0.7, color = 48,
      title = '~c~Concessionaire~s~ | Roxwood'
    },

    livraison = {                          -- ex-Config.Livraison
      spawnTruck  = vector4(-370.48574829102, 7438.6572265625, 6.2466268539429, 82.488479614258),
      toDelivery  = vector4(-350.53732299805, 7438.7309570312, 6.2498278617859, 263.45504760742),
      destination = vector4(-348.19348144531, 7438.8232421875, 6.2706613540649, 102.42668914795),
      stock       = vector4(-335.26187133789, 7406.2592773438, 6.3971085548401, 356.63186645508),
    },

    catalogue = {                          -- ex-Config.Catalogue + Preview + spawn
      coords  = vector4(-355.00646972656, 7469.7319335938, 6.4103851318359, 249.15939331055),
      preview = { coords = vector3(-351.53216552734, 7470.111328125, 6.4428567886353), heading = 41.469787597656 },
      spawn   = { coords = vector3(-373.30184936523, 7482.2543945312, 6.3313322067261), heading = 357.13214111328 },
      cam     = { enabled = true, coords = vector3(-357.54620361328, 7471.8969726562, 7.4104075431824), heading = 246.73239135742 },
    },

    comptoir = {                            -- ex-Config.Comptoir
      coords = vector4(-361.55163574219, 7468.6953125, 6.4103846549988, 14.429002761841),
      restockMultiplicateur = 0.3
    },

    coffre = {                              -- ex-Config.Coffre
      id = 'society_concess_roxwood',
      label = 'Concessionnaire Roxwood',
      slots = 50,
      weight = 100000,
      coords = vector4(-375.01113891602, 7446.7026367188, 6.410382270813, 5.8814344406128)
    },

    boss = {                                -- ex-Config.BossMenu
      coords = vector4(-375.79431152344, 7448.5444335938, 10.488301277161, 274.76452636719),
      maxSalary = 4000
    },


    AllowedCategories = {
		compacts=true, coupes=true, sedans=true, sports=true, sportsclassics=true,
		super=true, muscle=true, offroad=true, suvs=true, vans=true, motorcycles=true,
	},

    AllowedClasses    = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[12]=true },


    garagePed = { model = "a_m_m_og_boss_01", coords = vec3(-358.68060302734, 7444.6596679688, 6.3313255310059), heading = 178.61181640625 },
    wardrobes = {
      men   = { { coords = vec3(-1164.0475, -1694.8199, 9.8995), heading = 303.0586, icon="fas fa-hand-paper", labeltarget="Vestiaires Hommes" } },
      women = { { coords = vec3(-1167.4698, -1690.2875, 9.8996), heading = 303.7232, icon="fas fa-hand-paper", labeltarget="Vestiaires Femmes" } },
    },

	spots = {
		{ id=1,  name="Spot 1",  coords=vector4(170.5093536377, -1107.9982910156, 29.437797546387, 45.165828704834),  radius=3.5, type='car'  },
		{ id=2,  name="Spot 2",  coords=vector4(169.9697265625, -1113.7781982422, 29.319402694702, 82.396606445312),  radius=3.5, type='car' },
		{ id=3,  name="Spot 3",  coords=vector4(172.30178833008, -1100.13671875, 29.438737869263, 83.414009094238),  radius=3.5, type='car'  },
		{ id=4,  name="Spot 4",  coords=vector4(181.23960876465, -1107.947265625, 29.395620346069, 81.713973999023),  radius=3.5, type='car'  },
		{ id=5,  name="Spot 5",  coords=vector4(181.27851867676, -1103.859375, 29.395626068115, 85.411315917969),  radius=3.5, type='car'  },
		{ id=6,  name="Spot 6",  coords=vector4(181.07373046875, -1100.1496582031, 29.395626068115, 88.431327819824),  radius=3.5, type='car'  },
		{ id=7,  name="Spot 7",  coords=vector4(181.32106018066, -1095.8048095703, 29.395626068115, 94.383522033691),  radius=3.5, type='car'  },
		{ id=8,  name="Spot 8",  coords=vector4(174.48526000977, -1092.4284667969, 29.398904800415, 151.29991149902),  radius=3.5, type='bike'  },
		{ id=9,  name="Spot 9",  coords=vector4(172.52217102051, -1092.4184570312, 29.398910522461, 140.40110778809),  radius=3.5, type='bike'  },
		{ id=10,  name="Spot 10",  coords=vector4(170.57183837891, -1092.5119628906, 29.398864746094, 146.66734313965),  radius=3.5, type='bike'  },
		{ id=11,  name="Spot 11",  coords=vector4(168.55087280273, -1092.521484375, 29.401563644409, 151.51063537598),  radius=3.5, type='bike'  },
		{ id=12,  name="Spot 12",  coords=vector4(166.56048583984, -1092.6812744141, 29.398946762085, 150.65789794922),  radius=3.5, type='bike'  },
		{ id=13,  name="Spot 13",  coords=vector4(152.57662963867, -1091.828125, 29.438888549805, 244.51690673828),  radius=3.5, type='car'  },
		{ id=14,  name="Spot 14",  coords=vector4(151.02186584473, -1099.8616943359, 29.4387550354, 262.86505126953),  radius=3.5, type='car'  },
		{ id=15,  name="Spot 15",  coords=vector4(154.86836242676, -1113.8557128906, 29.319404602051, 269.52932739258),  radius=3.5, type='car'  },
	}
  },
}

Config.Uniforms = {
    employed = {
		male = {
			tshirt_1 = 15,  tshirt_2 = 0,
			torso_1 = 166,   torso_2 = 0,
			decals_1 = 0,   decals_2 = 0,
			arms = 0,
			pants_1 = 136,   pants_2 = 0,
			shoes_1 = 145,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = -1,
			chain_1 = 0,    chain_2 = 0,
			ears_1 = -1,     ears_2 = -1,
			bproof_1 = 45,  bproof_2 = 0
		},
		female = {
			tshirt_1 = 147,  tshirt_2 = 0,
			torso_1 = 310,   torso_2 = 0,
			decals_1 = 0,   decals_2 = 0,
			arms = 15,--bras
			pants_1 = 299,   pants_2 = 0,
			shoes_1 = 171,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,--casque
			chain_1 = 0,    chain_2 = 0,--chaine
			ears_1 = -1,     ears_2 = 0,--oreille
			bproof_1 = 88,  bproof_2 = 1  --armure
		}
	},
    avanced = {
		male = {
			tshirt_1 = 15,  tshirt_2 = 0,
			torso_1 = 166,   torso_2 = 0,
			decals_1 = 0,   decals_2 = 0,
			arms = 0,
			pants_1 = 136,   pants_2 = 0,
			shoes_1 = 145,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,
			chain_1 = 8,    chain_2 = 0,
			ears_1 = -1,     ears_2 = 0,
			bproof_1 = 51,  bproof_2 = 0
		},
		female = {
			tshirt_1 = 147,  tshirt_2 = 0,
			torso_1 = 310,   torso_2 = 0,
			decals_1 = 0,   decals_2 = 0,
			arms = 15,
			pants_1 = 299,   pants_2 = 0,
			shoes_1 = 171,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,
			chain_1 = 119,    chain_2 = 0,
			ears_1 = -1,     ears_2 = 0,
			bproof_1 = 15,  bproof_2 = 0
		}
	},
    leader = {
		male = {
			tshirt_1 = 15,  tshirt_2 = 0,
			torso_1 = 204,   torso_2 = 2,
			decals_1 = 0,   decals_2 = 0,
			arms = 0,
			pants_1 = 136,   pants_2 = 0,
			shoes_1 = 145,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,
			chain_1 = 8,    chain_2 = 0,
			ears_1 = -1,     ears_2 = 0,
			bproof_1 = 24,  bproof_2 = 4
		},
		female = {
			tshirt_1 = 147,  tshirt_2 = 0,
			torso_1 = 310,   torso_2 = 2,
			decals_1 = 0,   decals_2 = 0,
			arms = 15,
			pants_1 = 299,   pants_2 = 0,
			shoes_1 = 171,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,
			chain_1 = 119,    chain_2 = 0,
			ears_1 = -1,     ears_2 = 0,
			bproof_1 = 15,  bproof_2 = 0
		}
	},
	boss = {
		male = {
			tshirt_1 = 15,  tshirt_2 = 0,
			torso_1 = 204,   torso_2 = 2,
			decals_1 = 0,   decals_2 = 0,
			arms = 0,
			pants_1 = 136,   pants_2 = 0,
			shoes_1 = 145,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,
			chain_1 = 8,    chain_2 = 0,
			ears_1 = -1,     ears_2 = 0,
			bproof_1 = 24,  bproof_2 = 4
		},
		female = {
			tshirt_1 = 147,  tshirt_2 = 0,
			torso_1 = 310,   torso_2 = 2,
			decals_1 = 0,   decals_2 = 0,
			arms = 15,
			pants_1 = 299,   pants_2 = 0,
			shoes_1 = 171,   shoes_2 = 0,
			helmet_1 = -1,  helmet_2 = 0,
			chain_1 = 119,    chain_2 = 0,
			ears_1 = -1,     ears_2 = 0,
			bproof_1 = 15,  bproof_2 = 0
		}
	},  
}

