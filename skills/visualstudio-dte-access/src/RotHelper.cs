// Helper assembly for the visualstudio-dte-access skill.
//
// Provides two static classes:
//   ProcessHelper - fast P/Invoke parent-process walk via NtQueryInformationProcess.
//   RotHelper     - enumerates the Windows Running Object Table for COM monikers.
//
// Built to: ../scripts/RotHelper.dll  (see ../src/build.ps1)
// Targets .NET Framework 4.x / .NET 6+ (any TFM with the COM types below).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class ProcessHelper
{
    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_BASIC_INFORMATION
    {
        public IntPtr ExitStatus;
        public IntPtr PebBaseAddress;
        public IntPtr AffinityMask;
        public IntPtr BasePriority;
        public IntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(
        IntPtr handle, int infoClass, ref PROCESS_BASIC_INFORMATION pbi, int size, out int returned);

    /// <summary>Returns the parent PID of <paramref name="processId"/>, or 0 on failure.</summary>
    public static int GetParentProcessId(int processId)
    {
        try
        {
            using (var p = Process.GetProcessById(processId))
            {
                var pbi = new PROCESS_BASIC_INFORMATION();
                int returned;
                if (NtQueryInformationProcess(p.Handle, 0, ref pbi, Marshal.SizeOf(pbi), out returned) != 0) return 0;
                return pbi.InheritedFromUniqueProcessId.ToInt32();
            }
        }
        catch { return 0; }
    }

    /// <summary>
    /// Walks up the parent chain from <paramref name="startPid"/> and returns the first ancestor
    /// whose process name (case-insensitive, no extension) matches <paramref name="name"/>,
    /// or 0 if none found within 32 levels.
    /// </summary>
    public static int FindAncestorByName(int startPid, string name)
    {
        int current = startPid;
        for (int i = 0; i < 32 && current > 0; i++)
        {
            int parent = GetParentProcessId(current);
            if (parent <= 0) return 0;
            try
            {
                using (var p = Process.GetProcessById(parent))
                {
                    if (string.Equals(p.ProcessName, name, StringComparison.OrdinalIgnoreCase)) return parent;
                }
            }
            catch { return 0; }
            current = parent;
        }
        return 0;
    }
}

public static class RotHelper
{
    [DllImport("ole32.dll")]
    private static extern int GetRunningObjectTable(int reserved, out IRunningObjectTable rot);

    [DllImport("ole32.dll")]
    private static extern int CreateBindCtx(int reserved, out IBindCtx bindCtx);

    /// <summary>
    /// Returns (displayName, comObject) pairs for every ROT entry whose display name contains
    /// <paramref name="nameFragment"/>. Caller is responsible for releasing returned COM objects
    /// via Marshal.ReleaseComObject when done.
    /// </summary>
    public static List<KeyValuePair<string, object>> Find(string nameFragment)
    {
        var results = new List<KeyValuePair<string, object>>();
        IRunningObjectTable rot = null;
        IBindCtx bindCtx = null;
        IEnumMoniker enumMoniker = null;
        try
        {
            GetRunningObjectTable(0, out rot);
            CreateBindCtx(0, out bindCtx);
            rot.EnumRunning(out enumMoniker);
            var monikers = new IMoniker[1];
            // Passing IntPtr.Zero for pceltFetched is only valid when celt == 1.
            while (enumMoniker.Next(1, monikers, IntPtr.Zero) == 0)
            {
                var moniker = monikers[0];
                try
                {
                    moniker.GetDisplayName(bindCtx, null, out string displayName);
                    if (!string.IsNullOrEmpty(displayName) && displayName.Contains(nameFragment))
                    {
                        rot.GetObject(moniker, out object obj);
                        results.Add(new KeyValuePair<string, object>(displayName, obj));
                    }
                }
                finally
                {
                    Marshal.ReleaseComObject(moniker);
                }
            }
        }
        finally
        {
            if (enumMoniker != null) Marshal.ReleaseComObject(enumMoniker);
            if (bindCtx     != null) Marshal.ReleaseComObject(bindCtx);
            if (rot         != null) Marshal.ReleaseComObject(rot);
        }
        return results;
    }
}
