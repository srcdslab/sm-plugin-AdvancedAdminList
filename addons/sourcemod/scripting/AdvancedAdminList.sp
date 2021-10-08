#pragma semicolon 1

#include <sourcemod>
#include <multicolors>

#pragma newdecls required

#define DATABASE_NAME			"sourcebans"
#define COLOR_LIST_MAX_LENGTH	255

#define MAX_BUFFER_SIZE			1024

#define REBUILD_CACHE_WAIT_TIME 2.0

#define MAX_SB_GROUPS			256
#define MAX_COLOR_LEN			32

#define ADMIN_CONFIG_OVERRIDE	"advancedadminlist.cfg"

GroupId UNDEFINED_GROUP_ID = view_as<GroupId>(-2);
AdminId UNDEFINED_ADMIN_ID = view_as<AdminId>(-2);

GroupId	g_gGroups[MAXPLAYERS+1];
AdminId	g_gAdmins[MAXPLAYERS+1][MAXPLAYERS+1];

char	g_sResolvedAdminGroups[MAXPLAYERS+1][MAX_BUFFER_SIZE];
int		g_iResolvedAdminGroupsLength = 0;

ConVar g_cAdminsRealNames;
ConVar g_cAdminsNameColor;
ConVar g_cAdminsNameSeparatorColor;
ConVar g_cAdminsConfigMode;

bool g_bReloadAdminList = false;
bool g_bMapEnd = false;

Handle g_hDatabase = null;

char g_sColorList[COLOR_LIST_MAX_LENGTH][2][COLOR_LIST_MAX_LENGTH];
char g_sColorListOverride[COLOR_LIST_MAX_LENGTH][2][COLOR_LIST_MAX_LENGTH];
int g_iColorListSize = 0;
int g_iColorListOverrideSize = 0;

public Plugin myinfo =
{
	name = "Advanced Admin List",
	author = "maxime1907",
	description = "An advanced admin list system",
	version = "2.0",
	url = ""
};

public void OnPluginStart()
{
	g_cAdminsRealNames = CreateConVar("sm_admins_real_names", "1", "0 = disabled, 1 = enable in game admin name display", 0, true, 0.0, true, 1.0);
	g_cAdminsNameColor = CreateConVar("sm_admins_name_color", "{green}", "What color should be displayed for admin names");
	g_cAdminsNameSeparatorColor = CreateConVar("sm_admins_name_separator_color", "{default}", "What color should be displayed for separating admin names");
	g_cAdminsConfigMode = CreateConVar("sm_admins_config_mod", "2", "Configuration mode to load colors: 0 - SQL and .cfg overrides, 1 - SQL Only, 2 - .cfg only");

	g_cAdminsRealNames.AddChangeHook(OnCvarChanged);

	ReloadAdminList();

	AddCommandListener(Command_Admins, "sm_admins");

	RegAdminCmd("sm_admins_reloadcfgoverride", Command_ReloadConfigOverride, ADMFLAG_CONFIG, "Reloads the config override file for colors");

	AutoExecConfig(true);

	if (g_cAdminsConfigMode.IntValue == 0 || g_cAdminsConfigMode.IntValue == 1)
		SQLInitialize();

	if (g_cAdminsConfigMode.IntValue == 0 || g_cAdminsConfigMode.IntValue == 2)
		LoadConfigOverride(ADMIN_CONFIG_OVERRIDE);
}

public void OnPluginEnd()
{
	if (g_hDatabase != null)
		delete g_hDatabase;
}

public Action Command_ReloadConfigOverride(int client, int argc)
{
	for (int i = 0; i < g_iColorListOverrideSize; i++)
	{
		g_sColorListOverride[i][0] = "";
		g_sColorListOverride[i][1] = "";
	}
	g_iColorListOverrideSize = 0;

	if (LoadConfigOverride(ADMIN_CONFIG_OVERRIDE))
		CPrintToChat(client, "Successfully reloaded the admin config override");
	else
		CPrintToChat(client, "There was an error reloading the admin config override");
	return Plugin_Handled;
}

stock bool LoadConfigOverride(char[] sFilename)
{
	char sFilepath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilepath, sizeof(sFilepath), "configs/%s", sFilename);

	KeyValues kv = new KeyValues("AdvancedAdminList");

	if (!kv.ImportFromFile(sFilepath))
	{
		LogMessage("File missing, please make sure \"%s\" is in the \"sourcemod/configs\" folder.", sFilename);
		return false;
	}

	if (!kv.GotoFirstSubKey(false))
	{
		delete kv;
		return false;
	}

	do
	{
		kv.GetSectionName(g_sColorListOverride[g_iColorListOverrideSize][0], sizeof(g_sColorListOverride[][]));
		kv.GetString("color", g_sColorListOverride[g_iColorListOverrideSize][1], sizeof(g_sColorListOverride[][]));
		g_iColorListOverrideSize++;
	} while (kv.GotoNextKey(false));

	delete kv;
	return true;
}

stock void SQLInitialize()
{
	if (g_hDatabase != null)
		delete g_hDatabase;

	if (SQL_CheckConfig(DATABASE_NAME))
		SQL_TConnect(OnSQLConnected, DATABASE_NAME);
	else
		SetFailState("Could not find \"%s\" entry in databases.cfg.", DATABASE_NAME);
}

stock void OnSQLConnected(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Failed to connect to database \"%s\". (%s)", DATABASE_NAME, err);
		return;
	}

	char sDriver[16];
	g_hDatabase = CloneHandle(hChild);
	SQL_GetDriverIdent(hParent, sDriver, sizeof(sDriver));

	if (strncmp(sDriver, "my", 2, false))
	{
		LogError("Only mysql is supported for \"%s\".", DATABASE_NAME);
		return;

	}

	SQLSelect_Colors(INVALID_HANDLE);
}


stock Action SQLSelect_Colors(Handle timer)
{
	if (g_hDatabase == null)
		return Plugin_Stop;

	char sQuery[256];

	Format(sQuery, sizeof(sQuery), "SELECT `name`, `color` FROM `sb_srvgroups`;");
	SQL_TQuery(g_hDatabase, OnSQLSelect_Color, sQuery, 0, DBPrio_High);
	return Plugin_Stop;
}

public void OnSQLSelect_Color(Handle hParent, Handle hChild, const char[] err, any client)
{
	if (hChild == null)
	{
		LogError("An error occurred while querying the database for the admin group colors. (%s)", err);
		return;
	}

	while (SQL_FetchRow(hChild))
	{
		SQL_FetchString(hChild, 0, g_sColorList[g_iColorListSize][0], sizeof(g_sColorList[][]));
		SQL_FetchString(hChild, 1, g_sColorList[g_iColorListSize][1], sizeof(g_sColorList[][]));
		g_iColorListSize++;
	}

	ReloadAdminList();
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ReloadAdminList();
}

public void OnRebuildAdminCache(AdminCachePart part)
{
	// Only do something if admins are being rebuild
	if (part != AdminCache_Admins)
		return;

	CreateTimer(REBUILD_CACHE_WAIT_TIME, Timer_RebuildCache);
}

public Action Timer_RebuildCache(Handle hTimer)
{
	ReloadAdminList();
	return Plugin_Stop;
}

public void OnMapStart()
{
	g_bMapEnd = false;
}

public void OnMapEnd()
{
	g_bMapEnd = true;
}

public void OnClientPostAdminCheck(int client)
{
	if (g_bMapEnd)
		return;

	AdminId aid = GetUserAdmin(client);

	if (GetAdminFlag(aid, Admin_Generic))
		ReloadAdminList();
}

public void OnClientDisconnect(int client)
{
	if (g_bMapEnd)
		return;

	AdminId aid = GetUserAdmin(client);

	if (GetAdminFlag(aid, Admin_Generic))
		g_bReloadAdminList = true;
}

public void OnClientDisconnect_Post(int client)
{
	if (!g_bMapEnd && g_bReloadAdminList)
		ReloadAdminList();
}


//   .d8888b.   .d88888b.  888b     d888 888b     d888        d8888 888b    888 8888888b.   .d8888b.
//  d88P  Y88b d88P" "Y88b 8888b   d8888 8888b   d8888       d88888 8888b   888 888  "Y88b d88P  Y88b
//  888    888 888     888 88888b.d88888 88888b.d88888      d88P888 88888b  888 888    888 Y88b.
//  888        888     888 888Y88888P888 888Y88888P888     d88P 888 888Y88b 888 888    888  "Y888b.
//  888        888     888 888 Y888P 888 888 Y888P 888    d88P  888 888 Y88b888 888    888     "Y88b.
//  888    888 888     888 888  Y8P  888 888  Y8P  888   d88P   888 888  Y88888 888    888       "888
//  Y88b  d88P Y88b. .d88P 888   "   888 888   "   888  d8888888888 888   Y8888 888  .d88P Y88b  d88P
//   "Y8888P"   "Y88888P"  888       888 888       888 d88P     888 888    Y888 8888888P"   "Y8888P"
//

public Action Command_Admins(int client, const char[] command, int argc)
{
	if (!IsValidClient(client))
		return Plugin_Continue;

	printAdminList(client, g_sResolvedAdminGroups, g_iResolvedAdminGroupsLength);
	return Plugin_Stop;
}

// ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######  
// ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ## 
// ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##       
// ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######  
// ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ## 
// ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ## 
// ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######

public void printAdminList(int client, char[][] resolvedAdminsAndGroups, int resolvedAdminGroupsLength)
{
	CPrintToChat(client, "{green}[SM] {lightgreen}Admins %s", resolvedAdminGroupsLength <= 0 ? "are offline" : "currently online:");

	for (int i = 0; i < resolvedAdminGroupsLength; i++)
		CPrintToChat(client, resolvedAdminsAndGroups[i]);
}

public void ReloadAdminList()
{
	reloadAdminList(g_gGroups, g_gAdmins, g_sResolvedAdminGroups, g_iResolvedAdminGroupsLength);
}

public void reloadAdminList(GroupId[] groups, AdminId[][] names, char resolvedAdminGroups[MAXPLAYERS+1][MAX_BUFFER_SIZE], int &resolvedAdminGroupsLength)
{
	initAdminsAndGroups(groups, names, resolvedAdminGroups, resolvedAdminGroupsLength);
	getAdminsAndGroups(groups, names);
	resolveAdminsAndGroups(groups, names, resolvedAdminGroups, resolvedAdminGroupsLength);
	g_bReloadAdminList = false;
}

public void initAdminsAndGroups(GroupId[] groups, AdminId[][] names, char resolvedAdminGroups[MAXPLAYERS+1][MAX_BUFFER_SIZE], int iResolvedAdminGroups)
{
	int	y = 0;
	int	z = 0;

	while (y < MAXPLAYERS+1)
	{
		resolvedAdminGroups[y] = "";
		groups[y] = UNDEFINED_GROUP_ID;

		z = 0;
		while (z < MAXPLAYERS+1)
		{
			names[y][z] = UNDEFINED_ADMIN_ID;
			z++;
		}
		y++;
	}
}

public void getAdminsAndGroups(GroupId[] groups, AdminId[][] names)
{
	char group[64];

	int	i = 0;
	int	y = 0;
	int	z = 0;
	int j = 0;

	i = 1;
	while (i <= MaxClients)
	{
		if (IsValidClient(i))
		{
			AdminId aid = GetUserAdmin(i);

			if (GetAdminFlag(aid, Admin_Generic))
			{
				j = 0;
				int iGroupCount = GetAdminGroupCount(aid);
				GroupId gid = INVALID_GROUP_ID;
				while (j < iGroupCount)
				{
					gid = GetAdminGroup(aid, j, group, sizeof(group));
					if (gid != INVALID_GROUP_ID && (GetAdmGroupAddFlag(gid, Admin_Generic)
						|| GetAdmGroupAddFlag(gid, Admin_Root) || GetAdmGroupAddFlag(gid, Admin_RCON)))
						break;
					j++;
				}

				if (j >= iGroupCount)
				{
					i++;
					continue;
				}

				y = 0;
				while (groups[y] != UNDEFINED_GROUP_ID)
				{
					if (groups[y] == gid)
					{
						z = 0;
						while (names[y][z] != UNDEFINED_ADMIN_ID)
							z++;
						if (gid == INVALID_GROUP_ID)
							names[y][0] = view_as<AdminId>(i);
						else
							names[y][z] = aid;
						break;
					}
					y++;
				}

				if (groups[y] == UNDEFINED_GROUP_ID)
				{
					groups[y] = gid;
					if (gid == INVALID_GROUP_ID)
						names[y][0] = view_as<AdminId>(i);
					else
						names[y][0] = aid;
				}
			}
		}
		i++;
	}
}

public void resolveAdminsAndGroups(GroupId[] groups, AdminId[][] names, char resolvedAdminGroups[MAXPLAYERS+1][MAX_BUFFER_SIZE], int &resolvedAdminGroupsLength)
{
	char bufferName[MAX_NAME_LENGTH];
	char bufferAdminName[MAX_NAME_LENGTH];
	char name[MAX_NAME_LENGTH];

	char group[64];
	char groupColor[16];
	char buffer[MAX_BUFFER_SIZE];

	resolvedAdminGroupsLength = 0;
	int	y = 0;

	while (groups[resolvedAdminGroupsLength] != UNDEFINED_GROUP_ID)
	{
		y = 0;

		GroupId gid = GetAdminGroup(names[resolvedAdminGroupsLength][y], 0, group, sizeof(group));
		if (gid == INVALID_GROUP_ID)
			group = "Admin";
		else if (StrEqual(group, "VIP"))
			gid = GetAdminGroup(names[resolvedAdminGroupsLength][y], 1, group, sizeof(group));

		bool bFoundOverride = false;
		for (int i = 0; i < g_iColorListOverrideSize; i++)
		{
			if (StrEqual(g_sColorListOverride[i][0], group, true))
			{
				Format(groupColor, sizeof(groupColor), "{%s}", g_sColorListOverride[i][1]);
				bFoundOverride = true;
				break;
			}
		}

		if (!bFoundOverride)
		{
			for (int i = 0; i < g_iColorListSize; i++)
			{
				if (StrEqual(g_sColorList[i][0], group, true))
				{
					Format(groupColor, sizeof(groupColor), "{%s}", g_sColorList[i][1]);
					break;
				}
			}
		}

		if (g_iColorListSize <= 0 && g_iColorListOverrideSize <= 0 && !bFoundOverride)
			Format(groupColor, sizeof(groupColor), "{blue}");

		char sAdminNameColor[32];
		g_cAdminsNameColor.GetString(sAdminNameColor, sizeof(sAdminNameColor));

		char sAdminNameSeparatorColor[32];
		g_cAdminsNameSeparatorColor.GetString(sAdminNameSeparatorColor, sizeof(sAdminNameSeparatorColor));

		Format(buffer, sizeof(buffer), "%s[%s] %s", groupColor, group, sAdminNameColor);

		while (names[resolvedAdminGroupsLength][y] != UNDEFINED_ADMIN_ID)
		{
			bufferAdminName = "";
			if (gid == INVALID_GROUP_ID && !GetClientName(view_as<int>(names[resolvedAdminGroupsLength][y]), bufferName, sizeof(bufferName)))
			{
				Format(bufferName, sizeof(bufferName), "Disconnected: %d", names[resolvedAdminGroupsLength][y]);
				Format(name, sizeof(name), "%s", bufferName);
			}
			else
			{
				names[resolvedAdminGroupsLength][y].GetUsername(bufferAdminName, sizeof(bufferAdminName));
				if (StrEqual("", bufferAdminName))
					GetClientNameOfAdminId(names[resolvedAdminGroupsLength][y], bufferAdminName, sizeof(bufferAdminName));
				if (g_cAdminsRealNames.BoolValue && GetClientNameOfAdminId(names[resolvedAdminGroupsLength][y], bufferName, sizeof(bufferName)) && !StrEqual(bufferName, bufferAdminName))
					Format(name, sizeof(name), "%s (%s)", bufferAdminName, bufferName);
				else
					Format(name, sizeof(name), "%s", bufferAdminName);
			}

			if (y == 0)
				StrCat(buffer, sizeof(buffer), name);
			else
			{
				char sSeparator[64];
				Format(sSeparator, sizeof(sSeparator), "%s, %s", sAdminNameSeparatorColor, sAdminNameColor);
				StrCat(buffer, sizeof(buffer), sSeparator);
				StrCat(buffer, sizeof(buffer), name);
			}
			y++;
		}
		strcopy(resolvedAdminGroups[resolvedAdminGroupsLength], sizeof(resolvedAdminGroups[]), buffer);
		resolvedAdminGroupsLength++;
	}
}

public int GetClientOfAdminId(AdminId aid)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			AdminId foundAid = GetUserAdmin(i);
			if (aid == foundAid)
				return i;
		}
	}
	return 0;
}

public bool GetClientNameOfAdminId(AdminId aid, char[] name, int maxlen)
{
	int client = GetClientOfAdminId(aid);
	if (!client)
		return false;
	return GetClientName(client, name, maxlen);
}

bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
}