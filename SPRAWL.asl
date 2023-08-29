// SPRAWL Load remover + Autosplitter written by Meta and Micrologist.
// Giant shoutout to Micrologist for some fancy UE4 shit that works across most UE4 games or something? Huge.
state("Sprawl-Win64-Shipping"){}

startup
{
    vars.TimeOffset = -27.85;
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
}

init
{
    // Scanning the MainModule for static pointers to GSyncLoadCount, UWorld and FNamePool
    var scn = new SignatureScanner(game, game.MainModule.BaseAddress, game.MainModule.ModuleMemorySize);
    var syncLoadTrg = new SigScanTarget(5, "89 43 60 8B 05 ?? ?? ?? ??") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var syncLoadCounterPtr = scn.Scan(syncLoadTrg);
    var uWorldTrg = new SigScanTarget(8, "0F 2E ?? 74 ?? 48 8B 1D ?? ?? ?? ?? 48 85 DB 74") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var uWorld = scn.Scan(uWorldTrg);
    var fNamePoolTrg = new SigScanTarget(13, "89 5C 24 ?? 89 44 24 ?? 74 ?? 48 8D 15") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var fNamePool = scn.Scan(fNamePoolTrg);

    // Throwing in case any base pointers can't be found (yet, hopefully)
    if(syncLoadCounterPtr == IntPtr.Zero || uWorld == IntPtr.Zero || fNamePool == IntPtr.Zero)
    {
        throw new Exception("One or more base pointers not found - retrying");
    }

	vars.Watchers = new MemoryWatcherList
    {
        new MemoryWatcher<int>(new DeepPointer(syncLoadCounterPtr)) { Name = "syncLoadCount" }, // GSyncLoadCount
        new MemoryWatcher<ulong>(new DeepPointer(uWorld, 0x18)) { Name = "worldFName"}, // UWorld.Name
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
    vars.setStartTime = false;
    current.loading = old.loading = vars.Watchers["syncLoadCount"].Current > 0;
    current.world = old.world = vars.FNameToString(vars.Watchers["worldFName"].Current);
    vars.worldsVisited = new List<String>() { "NeoMenu", current.world };
    
    // Version detection, just in case
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
    // The game is loading if any scenes are loading synchronously
    current.loading = vars.Watchers["syncLoadCount"].Current > 0;

    // Get the current world name as string, only if *UWorld isnt null
    var worldFName = vars.Watchers["worldFName"].Current;
    current.world = worldFName != 0x0 ? vars.FNameToString(worldFName) : old.world;
}

start
{
    if(old.world == "NeoMenu" && current.world == "E1M1_Final") 
    {
        vars.startAfterLoad = true;
    }

    if(vars.startAfterLoad && !current.loading)
    {
        vars.startAfterLoad = false;
        vars.setStartTime = true;
        return true;
    }
}

onStart
{
    vars.worldsVisited = new List<String>() { "NeoMenu", current.world };
    
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
    // If the timer was autostarted by transitioning into E1M1, the game time should start on "vars.TimeOffset"
    if(vars.setStartTime)
    {
        vars.setStartTime = false;
        return TimeSpan.FromSeconds(vars.TimeOffset);
    }
}

split
{
    if(current.world != old.world && !vars.worldsVisited.Contains(current.world))
    {
        vars.worldsVisited.Add(current.world);
        return true;
    }
}
