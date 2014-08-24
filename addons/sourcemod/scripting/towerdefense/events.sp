#pragma semicolon 1

#include <sourcemod>

/**
 * Hooks all necessary events.
 * Some events may be hooked with EventHookMode_Pre or EventHookMode_Post.
 *
 * @noreturn
 */

stock HookEvents() {
	HookEvent("player_carryobject", Event_PlayerCarryObject);
	HookEvent("player_changeclass", Event_PlayerChangeClass);
	HookEvent("player_team", Event_PlayerChangeTeam, EventHookMode_Pre);
	HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_dropobject", Event_PlayerDropObject);
	HookEvent("post_inventory_application", Event_PostInventoryApplication, EventHookMode_Post);

	// User Messages
	HookUserMessage(GetUserMessageId("VGUIMenu"), Event_PlayerVGUIMenu, true);
}

public Event_PlayerCarryObject(Handle:hEvent, const String:sName[], bool:bDontBroadcast) {
	if (!g_bEnabled) {
		return;
	}

	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if (IsDefender(iClient)) {
		g_bCarryingObject[iClient] = true;
	}

	return;
}

public Event_PlayerChangeClass(Handle:hEvent, const String:sName[], bool:bDontBroadcast) {
	if (!g_bEnabled) {
		return;
	}

	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if (IsValidClient(iClient) && !IsFakeClient(iClient)) {
		TF2_SetPlayerClass(iClient, TFClass_Engineer, false, true);
	}
}

public Action:Event_PlayerChangeTeam(Handle:hEvent, const String:sName[], bool:bDontBroadcast) {
	if (!g_bEnabled) {
		return Plugin_Continue;
	}

	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	SetEventBroadcast(hEvent, true); // Block the chat output (Player ... joined team BLU)
	
	if (IsValidClient(iClient) && !IsFakeClient(iClient)) {
		PrintToChatAll("Player %N joined the Defenders.", iClient);
	}

	return Plugin_Continue;
}

public Action:Event_PlayerConnect(Handle:hEvent, const String:sName[], bool:bDontBroadcast) {
	if (!g_bEnabled) {
		return Plugin_Continue;
	}

	SetEventBroadcast(hEvent, true); // Block the original chat output (Player ... has joined the game)
	
	return Plugin_Continue;
}

public Event_PlayerDropObject(Handle:hEvent, const String:sName[], bool:bDontBroadcast) {
	if (!g_bEnabled) {
		return;
	}

	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));

	if (IsDefender(iClient)) {
		g_bCarryingObject[iClient] = false;
	}

	return;
}

public Event_PostInventoryApplication(Handle:hEvent, const String:sName[], bool:bDontBroadcast) {
	if (!g_bEnabled) {
		return;
	}

	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));

	if (IsDefender(iClient)) {
		ResetClientMetal(iClient);
		SetEntProp(iClient, Prop_Data, "m_bloodColor", _:TDBlood_None);

		if (g_bReplaceWeapon[iClient][TFWeaponSlot_Primary]) {
			TF2Items_GiveWeapon(iClient, 9, TFWeaponSlot_Primary, 5, 1, true, "tf_weapon_shotgun_primary", "");
			
			g_bReplaceWeapon[iClient][TFWeaponSlot_Primary] = false;
		}

		if (g_bReplaceWeapon[iClient][TFWeaponSlot_Secondary]) {
			TF2Items_GiveWeapon(iClient, 22, TFWeaponSlot_Secondary, 5, 1, true, "tf_weapon_pistol", "");
			
			g_bReplaceWeapon[iClient][TFWeaponSlot_Secondary] = false;
		}
	} else if (IsTower(iClient)) {
		SetEntProp(iClient, Prop_Data, "m_bloodColor", _:TDBlood_None);
		SetRobotModel(iClient);
	}
}

/*====================================
=            Usermessages            =
====================================*/

public Action:Event_PlayerVGUIMenu(UserMsg:iMessageId, Handle:hBitBuffer, const iPlayers[], iPlayersNum, bool:bReliable, bool:bInit) {
	decl String:sBuffer1[64];
	decl String:sBuffer2[256];

	// check menu name
	BfReadString(hBitBuffer, sBuffer1, sizeof(sBuffer1));
	if (strcmp(sBuffer1, "info") != 0) {
		return Plugin_Continue;
	}

	// Skip hidden motd
	if (BfReadByte(hBitBuffer) != 1) {
		return Plugin_Continue;
	}
	
	new iCount = BfReadByte(hBitBuffer);

	if (iCount == 0) {
		return Plugin_Continue;
	}

	new Handle:hKeyValues = CreateKeyValues("data");

	for (new i = 0; i < iCount; i++) {
		BfReadString(hBitBuffer, sBuffer1, sizeof(sBuffer1));
		BfReadString(hBitBuffer, sBuffer2, sizeof(sBuffer2));
		
		if (StrEqual(sBuffer1, "customsvr") || (StrEqual(sBuffer1, "msg") && !StrEqual(sBuffer2, "motd"))) {
			CloseHandle(hKeyValues);
			return Plugin_Continue;
		}
		
		KvSetString(hKeyValues, sBuffer1, sBuffer2);
	}

	new Handle:hPack;

	CreateDataTimer(0.0, ShowMotd, hPack, TIMER_FLAG_NO_MAPCHANGE);

	WritePackCell(hPack, GetClientUserId(iPlayers[0]));
	WritePackCell(hPack, _:hKeyValues);
	
	return Plugin_Handled;
}

public Action:ShowMotd(Handle:hTimer, Handle:hPack) {
	ResetPack(hPack);

	new iClient = GetClientOfUserId(ReadPackCell(hPack));
	new Handle:hKeyValues = Handle:ReadPackCell(hPack);
	
	if (!IsValidClient(iClient)) {
		CloseHandle(hKeyValues);
		return Plugin_Stop;
	}

	KvSetNum(hKeyValues, "customsvr", 1);
	KvSetNum(hKeyValues, "cmd", 5); // closed_htmlpage
	KvSetNum(hKeyValues, "type", MOTDPANEL_TYPE_URL);

	KvSetString(hKeyValues, "title", "Welcome to TF2 Tower Defense!");
	KvSetString(hKeyValues, "msg", "http://www.tf2td.net/");

	ShowVGUIPanel(iClient, "info", hKeyValues, true);

	CloseHandle(hKeyValues);

	return Plugin_Stop;
}

/*==================================
=            TF2 Events            =
==================================*/

/**
 * Called on weapon fire to decide if the current shot should be critical.
 *
 * @noreturn
 */

public Action:TF2_CalcIsAttackCritical(iClient, iWeapon, String:sClassname[], &bool:bResult) {
	if (!g_bEnabled) {
		return Plugin_Handled;
	}

	if (StrEqual(sClassname, "tf_weapon_wrench") || StrEqual(sClassname, "tf_weapon_robot_arm")) {
		new Float:fLocation[3], Float:fAngles[3];

		GetClientEyePosition(iClient, fLocation);
		GetClientEyeAngles(iClient, fAngles);
			
		TR_TraceRayFilter(fLocation, fAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceRayPlayers, iClient);
		
		if (TR_DidHit()) {
			new iTower = TR_GetEntityIndex();
		
			if (IsTower(iTower)) {
				new Float:fHitLocation[3];
				TR_GetEndPosition(fHitLocation);

				if (GetVectorDistance(fLocation, fHitLocation) <= 70.0) {
					UpgradeTower(iTower, iClient);
				}
			}
		}
	}

	return Plugin_Handled;
}

/*=======================================
=            TF2Items Events            =
=======================================*/

/**
 * Called when an item was given to a client.
 *
 * @noreturn
 */

public TF2Items_OnGiveNamedItem_Post(iClient, String:sClassname[], iItemDefinitionIndex, iItemLevel, iItemQuality, iEntityIndex) {
	if (!g_bEnabled) {
		return;
	}

	if (!IsDefender(iClient)) {
		return;
	}

	if (iItemDefinitionIndex != 9 || iItemDefinitionIndex != 199) {
		// Engineers primaries => Engineer's Shotgun

		g_bReplaceWeapon[iClient][TFWeaponSlot_Primary] = true;
	}

	if (iItemDefinitionIndex != 22 || iItemDefinitionIndex != 209 || iItemDefinitionIndex != 160 || iItemDefinitionIndex != 294) {
		// Engineers secondaries => Engineer's Pistol 
		
		g_bReplaceWeapon[iClient][TFWeaponSlot_Secondary] = true;
	}
}