// SPRAWL Load remover + Autosplitter written by Meta and Micrologist
state("Sprawl-Win64-Shipping"){}

startup
{
    if (timer.CurrentTimingMethod == TimingMethod.RealTime)
    {
        var timingMessage = MessageBox.Show (
            "This game uses Time without Loads (Game Time) as the main timing method.\n"+
            "LiveSplit is currently set to show Real Time (RTA).\n"+
            "Would you like to set the timing method to Game Time?",
            "LiveSplit | SPRAWL",
            MessageBoxButtons.YesNo,MessageBoxIcon.Question
        );

        if (timingMessage == DialogResult.Yes)
        {
            timer.CurrentTimingMethod = TimingMethod.GameTime;
        }
    }

    settings.Add("ILMode", false, "Start the timer when loading into any level (IL Mode)");
}

init
{
    // Scanning the MainModule for static pointers to GSyncLoadCount, UWorld, UEngine and FNamePool
    var scn = new SignatureScanner(game, game.MainModule.BaseAddress, game.MainModule.ModuleMemorySize);
    var syncLoadTrg = new SigScanTarget(5, "89 43 60 8B 05 ?? ?? ?? ??") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var syncLoadCounterPtr = scn.Scan(syncLoadTrg);
    var uWorldTrg = new SigScanTarget(8, "0F 2E ?? 74 ?? 48 8B 1D ?? ?? ?? ?? 48 85 DB 74") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var uWorld = scn.Scan(uWorldTrg);
    var gameEngineTrg = new SigScanTarget(3, "48 39 35 ?? ?? ?? ?? 0F 85 ?? ?? ?? ?? 48 8B 0D") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var gameEngine = scn.Scan(gameEngineTrg);
    var fNamePoolTrg = new SigScanTarget(13, "89 5C 24 ?? 89 44 24 ?? 74 ?? 48 8D 15") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var fNamePool = scn.Scan(fNamePoolTrg);

    // Throwing in case any base pointers can't be found (yet, hopefully)
    if(syncLoadCounterPtr == IntPtr.Zero || uWorld == IntPtr.Zero || gameEngine == IntPtr.Zero || fNamePool == IntPtr.Zero)
    {
        throw new Exception("One or more base pointers not found - retrying");
    }

	vars.Watchers = new MemoryWatcherList
    {
        // GSyncLoadCount
        new MemoryWatcher<int>(new DeepPointer(syncLoadCounterPtr)) { Name = "syncLoadCount" },
        // UWorld.Name
        new MemoryWatcher<ulong>(new DeepPointer(uWorld, 0x18)) { Name = "worldFName"},
        // GameEngine.GameInstance.LocalPlayers[0].PlayerController.PlayerCameraManager.ViewTarget.Target.Name
        new MemoryWatcher<ulong>(new DeepPointer(gameEngine, 0xD28, 0x38, 0x0, 0x30, 0x2B8, 0xE90, 0x18)) { Name = "camViewTargetFName"},
        // GameEngine.Gameinstance.LocalPlayers[0].PlayerController.MyHUD.PawnSpecificWidgets[0].UI_LevelEndScreen
        //new MemoryWatcher<IntPtr>(new DeepPointer(gameEngine, 0xD28, 0x38, 0x0, 0x30, 0x2B0, 0x310, 0x0, 0x2E0)) { Name = "levelEndScreenPtr"},
    };

    // Translating FName to String, this *could* be cached
    vars.FNameToString = (Func<ulong, string>)(fName =>
    {
        var number   = (fName & 0xFFFFFFFF00000000) >> 0x20;
        var chunkIdx = (fName & 0x00000000FFFF0000) >> 0x10;
        var nameIdx  = (fName & 0x000000000000FFFF) >> 0x00;
        var chunk = game.ReadPointer(fNamePool + 0x10 + (int)chunkIdx * 0x8);
        var nameEntry = chunk + (int)nameIdx * 0x2;
        var length = game.ReadValue<short>(nameEntry) >> 6;
        var name = game.ReadString(nameEntry + 0x2, length);
        return number == 0 ? name : name + "_" + number;
    });

    vars.Watchers.UpdateAll(game);

    vars.startAfterLoad = false;
    current.loading = old.loading = vars.Watchers["syncLoadCount"].Current > 0;
    current.world = old.world = vars.FNameToString(vars.Watchers["worldFName"].Current);
    vars.worldsVisited = new List<String>() { "Credits_Map", "NeoMenu", current.world };
    vars.startTime = 0f;
    vars.setStartTime = false;
    
    // Version detection, just in case anything breaks
    int moduleSize = modules.First().ModuleMemorySize;
    switch (moduleSize) 
    {
        case 0x53C2000:
            version = "Steam v1.0";
            break;
        default:                                
            version = "Unknown " + moduleSize.ToString("X8");
            break;
    }
}

update
{
    vars.Watchers.UpdateAll(game);

    // The game is considered to be loading if any scenes are loading synchronously
    current.loading = vars.Watchers["syncLoadCount"].Current > 0;

    // Get the current world name as string, only if *UWorld isnt null
    var worldFName = vars.Watchers["worldFName"].Current;
    current.world = worldFName != 0x0 ? vars.FNameToString(worldFName) : old.world;

    // Get the Name of the current target for the CameraManager
    current.camTarget = vars.FNameToString(vars.Watchers["camViewTargetFName"].Current);

    /* Check if the end screen is visible but not closeable
    var endScreenPtr = vars.Watchers["levelEndScreenPtr"].Current;
    var waitingForEndScreen = endScreenPtr != IntPtr.Zero ? game.ReadValue<byte>((IntPtr)endScreenPtr+0xC3) == 0x0 && !game.ReadValue<bool>((IntPtr)endScreenPtr+0x2E8) : false;
    */

}

start
{
    if(old.world == "NeoMenu" && current.world != old.world && (current.world == "E1M1_Final" || settings["ILMode"]))
    {
        vars.startAfterLoad = true;
    }

    if(vars.startAfterLoad && !current.loading)
    {
        vars.startAfterLoad = false;
        if(current.world == "E1M1_Final")
        {
            vars.startTime = -27.85f;
            vars.setStartTime = true;
        }
        return true;
    }
}

onStart
{
    vars.worldsVisited = new List<String>() { "Credits_Map", "NeoMenu", current.world };
    
    // This keeps the timer at 00:00 if the run is manually started during loading
    if(current.loading)
    {
        timer.IsGameTimePaused = true;
    }
}

isLoading
{
    return current.loading;
}

gameTime 
{   
    if(vars.setStartTime)
    {
        vars.setStartTime = false;
        return TimeSpan.FromSeconds(vars.startTime);
    }
}

split
{
    if(current.world != old.world && !vars.worldsVisited.Contains(current.world))
    {
        vars.worldsVisited.Add(current.world);
        return true;
    }

    // This tracks the transition to cutscene at the end of E3M3
    if(current.world == "E3M3" && current.camTarget != old.camTarget && current.camTarget == "CameraActor_2")
    {
        return true;
    }
}
