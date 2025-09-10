# AdvancedAdminList - Copilot Instructions

This repository contains a SourcePawn plugin for SourceMod that provides an advanced admin list system for Source engine game servers. This plugin displays online administrators with customizable colors, multiple sorting options, and integration with SourceBans database.

## Repository Overview

**Plugin Purpose**: Displays a formatted list of online administrators with colors, group information, and real names, supporting multiple display modes and database integration.

**Key Features**:
- Customizable admin display with color coding
- Multiple sorting modes (alphabetical, immunity level, config order)
- SourceBans database integration for group colors
- Configuration override system
- Real names display option
- Multi-language support through MultiColors

## Technical Environment

- **Language**: SourcePawn
- **Platform**: SourceMod 1.11.0+ (latest stable recommended)
- **Build Tool**: SourceKnight (configured via `sourceknight.yaml`)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight
- **CI/CD**: GitHub Actions (`.github/workflows/ci.yml`)

## Development Setup

### Dependencies
- **SourceMod**: 1.11.0-git6917 (auto-downloaded by SourceKnight)
- **MultiColors**: Latest from srcdslab/sm-plugin-MultiColors (auto-downloaded)

### Build Process
```bash
# SourceKnight handles dependency management and compilation
# No manual setup required - dependencies are automatically fetched
```

### File Structure
```
addons/sourcemod/
├── scripting/
│   └── AdvancedAdminList.sp          # Main plugin source
├── configs/
│   └── advancedadminlist.cfg         # Color and group configuration
└── plugins/                          # Compiled output (auto-generated)
    └── AdvancedAdminList.smx
```

## Code Standards & Architecture

### SourcePawn Conventions Used
- `#pragma semicolon 1` and `#pragma newdecls required` enforced
- Global variables prefixed with `g_`
- PascalCase for functions, camelCase for local variables
- Tab indentation (4 spaces)
- Memory management: Use `delete` directly (no null checks needed)
- All SQL operations are asynchronous using methodmap

### Key Components

**Core Data Structures**:
- `g_gGroups[]`: Stores GroupId for each admin group
- `g_gAdmins[][]`: 2D array storing AdminId for each group's admins
- `g_sResolvedAdminGroups[][]`: Final formatted strings for display
- `g_sColorList[][]` & `g_sColorListOverride[][]`: Color mappings

**Main Functions**:
- `OnPluginStart()`: Initialization, ConVar setup, database connection
- `ReloadAdminList()`: Core function that rebuilds the admin list
- `resolveAdminsAndGroups()`: Formats final display strings with colors
- Sorting functions: `SortAdminGroups*()` for different sort modes

**Configuration System**:
- ConVars for display options and behavior
- `.cfg` file for group colors and display order
- Database integration for SourceBans group colors
- Three modes: SQL+cfg override, SQL only, cfg only

## Common Development Tasks

### Adding New Features
1. **New ConVars**: Add in `OnPluginStart()`, include change hooks
2. **New Commands**: Use `RegAdminCmd()` with appropriate flags
3. **Color Changes**: Modify config file or database table `sb_srvgroups`
4. **Sorting Options**: Extend the sorting system in `resolveAdminsAndGroups()`

### Modifying Display Logic
- Core display logic is in `resolveAdminsAndGroups()`
- Color resolution happens through override system (cfg → database → default)
- Group filtering (e.g., VIP exclusion) is in the group resolution loop

### Database Operations
- All SQL queries must be asynchronous (`SQL_TQuery`)
- Connection handling is in `SQLInitialize()` and `OnSQLConnected()`
- Only supports MySQL/MariaDB (`sb_srvgroups` table)

## Testing & Validation

### Manual Testing
1. Load plugin on a test server with SourceMod
2. Test with different admin configurations
3. Verify color display and sorting modes
4. Test database connectivity if using SourceBans

### Code Validation
- Plugin compiles without warnings via SourceKnight
- Follow SourcePawn memory management best practices
- Ensure proper error handling for database operations

## Performance Considerations

### Optimization Notes
- Admin list rebuilding uses O(n) algorithms where possible
- Caching system prevents excessive rebuilds (`g_bRebuildInProgress`)
- Timer-based rebuilding with delay (`REBUILD_CACHE_WAIT_TIME`)
- Efficient string operations using SourcePawn natives

### Memory Management
- Use `delete` for handles without null checks
- Avoid `.Clear()` on StringMap/ArrayList (creates memory leaks)
- Proper cleanup in `OnPluginEnd()`

## Common Issues & Solutions

### Build Issues
- Ensure all dependencies are properly declared in `sourceknight.yaml`
- Check SourceMod version compatibility
- Verify include files are accessible

### Runtime Issues
- **Empty admin list**: Check admin flags and group assignments
- **Color not displaying**: Verify MultiColors installation and config
- **Database errors**: Ensure SourceBans database configuration is correct
- **Sorting problems**: Check group names match between config and database

### Configuration Issues
- Config file must use exact group names from SourceMod admin system
- Database table `sb_srvgroups` must exist for database mode
- ConVar changes trigger automatic list rebuilds

## Integration Points

### SourceBans Integration
- Table: `sb_srvgroups` (columns: `name`, `color`)
- Database config: Uses `"sourcebans"` entry in `databases.cfg`
- Fallback to config file if database unavailable

### MultiColors Dependency
- Required for color formatting in chat
- Provides `CPrintToChat()` functionality
- Must be loaded before this plugin

## Best Practices for Modifications

1. **Preserve existing functionality**: This plugin is mature and stable
2. **Follow memory patterns**: Use existing patterns for handle management
3. **Maintain compatibility**: Keep ConVar names and behavior consistent
4. **Test thoroughly**: Changes affect critical admin functionality
5. **Document changes**: Update config examples if adding new features
6. **Respect sorting modes**: Ensure new features work with all sort options

## File Modification Guidelines

- **Main plugin** (`AdvancedAdminList.sp`): Core logic changes
- **Config file** (`advancedadminlist.cfg`): Group colors and display order
- **Build config** (`sourceknight.yaml`): Dependencies and build targets
- **CI/CD** (`.github/workflows/ci.yml`): Build and release automation

## SourcePawn-Specific Guidelines

### Variable Declarations
```sourcepawn
// Correct patterns used in this codebase
ConVar g_cVariableName;           // Global ConVars with g_c prefix
char g_sStringVariable[256];      // Global strings with g_s prefix
int g_iIntegerVariable;           // Global integers with g_i prefix
bool g_bBooleanVariable;          // Global booleans with g_b prefix
Handle g_hHandleVariable;         // Global handles with g_h prefix
```

### Memory Management Patterns
```sourcepawn
// Correct: Direct deletion (used throughout this plugin)
delete g_hDatabase;

// Correct: No null checks needed before delete
delete kv;

// Avoid: Using .Clear() on StringMap/ArrayList (creates memory leaks)
// Instead: delete and recreate
```

### SQL Best Practices (Used in this plugin)
```sourcepawn
// All SQL operations are asynchronous
SQL_TQuery(g_hDatabase, OnSQLSelect_Color, sQuery, 0, DBPrio_High);

// Proper error handling in callbacks
public void OnSQLSelect_Color(Handle hParent, Handle hChild, const char[] err, any client)
{
    if (hChild == null)
    {
        LogError("Database error: %s", err);
        return;
    }
    // Process results...
}
```

### Plugin Structure Patterns
```sourcepawn
// Standard plugin hooks used
public void OnPluginStart()         // Initialization
public void OnPluginEnd()           // Cleanup (if needed)
public void OnMapStart()            // Map-specific initialization
public void OnClientPostAdminCheck(int client)  // Admin status changes
```

## Version Management

- Plugin version is defined in `myinfo` structure (currently "2.1.2")
- Update version when making significant changes
- CI automatically creates releases with tags
- Follow semantic versioning: MAJOR.MINOR.PATCH

When making changes, always consider the impact on existing server configurations and admin workflows.