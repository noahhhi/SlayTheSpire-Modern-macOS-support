package com.megacrit.mtslauncher;

import com.codedisaster.steamworks.SteamNativeHandle;
import com.codedisaster.steamworks.SteamPublishedFileID;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.logging.Logger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Local Workshop lookup for the legacy launcher. No native Steam initialization. */
class MtsFinder {
    private static final Logger logger = Logger.getLogger(MtsFinder.class.getName());
    private static final Pattern PAIR = Pattern.compile(
        "(?m)^\\s*\"((?:\\\\.|[^\"\\\\])*)\"[ \\t]*\"((?:\\\\.|[^\"\\\\])*)\"");

    String findModLauncher(int appId, SteamPublishedFileID modId, Path target) {
        logger.info("Local Workshop lookup enabled; native Steam discovery is bypassed.");
        if (appId != 646570 || target == null || target.isAbsolute()
                || target.normalize().startsWith("..") || modId == null) {
            logger.severe("Unsupported app ID or invalid Workshop target.");
            return null;
        }
        try {
            Files.write(Paths.get("steam_appid.txt"), "646570".getBytes(StandardCharsets.UTF_8));
        } catch (IOException e) {
            logger.severe("Cannot write steam_appid.txt: " + e);
            return null;
        }
        Set<Path> libraries = new LinkedHashSet<Path>();
        // Prefer the game's own library, if launched inside a Steam installation.
        for (Path p = Paths.get("").toAbsolutePath(); p != null; p = p.getParent()) {
            if (p.getFileName() != null && p.getFileName().toString().equals("steamapps")) {
                libraries.add(p.getParent());
                break;
            }
        }
        Path steam = Paths.get(System.getProperty("user.home"), "Library", "Application Support", "Steam");
        libraries.add(steam);
        readLibraries(steam.resolve("steamapps/libraryfolders.vdf"), libraries);
        readLibraries(steam.resolve("config/libraryfolders.vdf"), libraries);
        String item = Long.toUnsignedString(SteamNativeHandle.getNativeHandle(modId));
        for (Path library : libraries) {
            Path jar = library.resolve("steamapps/workshop/content")
                .resolve(Integer.toString(appId)).resolve(item).resolve(target).normalize();
            logger.info("Checking local Workshop path: " + jar);
            if (Files.isRegularFile(jar) && Files.isReadable(jar)) {
                logger.info("Found ModTheSpire in local Workshop: " + jar);
                return jar.toAbsolutePath().toString();
            }
        }
        logger.severe("ModTheSpire is not downloaded in any local Steam library. "
            + "Subscribe in Steam and wait for Workshop downloads to finish: "
            + "https://steamcommunity.com/sharedfiles/filedetails/?id=" + item);
        return null;
    }

    private static void readLibraries(Path vdf, Set<Path> libraries) {
        if (!Files.isRegularFile(vdf)) return;
        try {
            Matcher pairs = PAIR.matcher(new String(Files.readAllBytes(vdf), StandardCharsets.UTF_8));
            while (pairs.find()) {
                String key = pairs.group(1);
                if (!key.equalsIgnoreCase("path") && !key.matches("[0-9]+")) continue;
                String value = pairs.group(2).replace("\\\"", "\"").replace("\\\\", "\\");
                Path path = Paths.get(value);
                if (path.isAbsolute()) libraries.add(path.normalize());
            }
        } catch (IOException | IllegalArgumentException e) {
            logger.warning("Cannot read Steam library list " + vdf + ": " + e);
        }
    }
}
