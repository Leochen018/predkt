let _plugin = null;

async function getPlugin() {
  if (_plugin !== undefined) return _plugin;
  try {
    const mod = await import("@capacitor/local-notifications");
    _plugin = mod.LocalNotifications;
  } catch {
    _plugin = null;
  }
  return _plugin;
}

export async function requestNotificationPermission() {
  const plugin = await getPlugin();
  if (!plugin) return false;
  try {
    const result = await plugin.requestPermissions();
    return result.display === "granted";
  } catch {
    return false;
  }
}

export async function scheduleMatchReminder(match) {
  const plugin = await getPlugin();
  if (!plugin || !match?.rawDate) return false;
  const kickoff  = new Date(match.rawDate);
  const notifyAt = new Date(kickoff.getTime() - 30 * 60 * 1000); // 30 min before
  if (notifyAt <= new Date()) return false;
  try {
    await plugin.schedule({
      notifications: [{
        id:    match.id || Math.floor(Math.random() * 1e6),
        title: "Match Reminder",
        body:  `${match.home} vs ${match.away} kicks off in 30 minutes`,
        schedule: { at: notifyAt },
        sound: "default",
      }],
    });
    return true;
  } catch {
    return false;
  }
}
