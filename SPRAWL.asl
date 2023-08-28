// SPRAWL Load remover + Autosplitter written by Meta and Micrologist.
// Giant shoutout to Micrologist for some fancy UE4 shit that works across most UE4 games or something? Huge.

state("Sprawl-Win64-Shipping", "Steam v1.0")
{
    string150 mission : 0x04F04720, 0x8B0, 0x0;
}

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
        new MemoryWatcher<int>(new DeepPointer(syncLoadCounterPtr)) { Name = "syncLoadCount" },
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

    vars.startAfterLoad = false;
    vars.setStartTime = false;
    current.loading = old.loading = false;
    current.world = old.world = "";

    // Version detection, just in case
    switch (modules.First().ModuleMemorySize) 
    {
        case 87826432:
            version = "Steam v1.0";
            break;
        default:
            print("Unknown version detected");
            break;
    }
}

onStart
{
    // part of the autostart countdown
    vars.setStartTime = true;
}

gameTime 
{   
    //part of the autostart countdown
    if(vars.setStartTime)
    {
        vars.setStartTime = false;
        return TimeSpan.FromSeconds(vars.TimeOffset);
    }
}  

update
{
    vars.Watchers.UpdateAll(game);
    // The game is loading if any scenes are loading synchronously
    current.loading = vars.Watchers["syncLoadCount"].Current > 0;

    // Get the current world name as string, only if *UWorld isnt null
    var worldFName = vars.Watchers["worldFName"].Current;
    current.world = worldFname != 0x0 ? vars.FNameToString(worldFName) : old.world;
}

start
{
    if(old.world == "NeoMenu" && current.world != "NeoMenu")
    {
        vars.startAfterLoad = true;
    }

    if(vars.startAfterLoad && !current.loading)
    {
        vars.startAfterLoad = false;
        return true;
    }
}

isLoading
{
    return current.loading;
}

/* Micrologists magic autosplitting, doesn't appear to work with Sprawl but gonna keep it here for reference
split
{
    return old.world != current.world  && current.world != "NeoMenu";
}
*/

split
{   // will clean this up later but it seems to work perfectly fine lol
    return old.mission != current.mission && current.mission != "/Game/Maps/NeoMenu";
}