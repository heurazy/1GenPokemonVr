package com.maniscat2.sm64coopdx;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public final class RomPickerActivity extends Activity {
    private static final int REQUEST_ROM = 6401;
    private static final int ROM_SIZE = 8 * 1024 * 1024;
    private static final int MAX_SIZE = 32 * 1024 * 1024;
    private static final String ROM_SHA1 = "9bef1128717f958171a4afac3ed78ee2bb4e86ce";
    private static final String ROM_NAME = "baserom.us.z64";

    private TextView status;
    private Button choose;
    private Button play;
    private ProgressBar progress;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE);
        hideSystemUi();
        createUi();
        verifyCurrentRom();
    }

    @Override
    public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        if (focused) hideSystemUi();
    }

    private void hideSystemUi() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    private void createUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(dp(24), dp(24), dp(24), dp(24));
        root.setBackgroundColor(Color.rgb(10, 14, 24));

        TextView title = text("Mario 64", 34, Color.WHITE);
        root.addView(title, fullWrap());

        TextView info = text("Choisis ta ROM originale Super Mario 64 US.\nFormats : .z64, .v64, .n64 ou .zip", 18,
                Color.rgb(200, 210, 225));
        LinearLayout.LayoutParams infoParams = fullWrap();
        infoParams.setMargins(0, dp(12), 0, dp(18));
        root.addView(info, infoParams);

        status = text("", 17, Color.WHITE);
        LinearLayout.LayoutParams statusParams = fullWrap();
        statusParams.setMargins(0, 0, 0, dp(16));
        root.addView(status, statusParams);

        progress = new ProgressBar(this);
        progress.setIndeterminate(true);
        progress.setVisibility(View.GONE);
        root.addView(progress, new LinearLayout.LayoutParams(dp(48), dp(48)));

        choose = new Button(this);
        choose.setText("Choisir une ROM");
        choose.setTextSize(18);
        choose.setOnClickListener(v -> openPicker());
        root.addView(choose, buttonParams());

        play = new Button(this);
        play.setText("Lancer Mario 64");
        play.setTextSize(18);
        play.setVisibility(View.GONE);
        play.setOnClickListener(v -> launchGame());
        LinearLayout.LayoutParams playParams = buttonParams();
        playParams.setMargins(0, dp(12), 0, 0);
        root.addView(play, playParams);
        setContentView(root);
    }

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER);
        return view;
    }

    private LinearLayout.LayoutParams fullWrap() {
        return new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams buttonParams() {
        return new LinearLayout.LayoutParams(dp(340), dp(58));
    }

    private void verifyCurrentRom() {
        busy(true, "Vérification de la ROM…");
        new Thread(() -> {
            boolean valid = false;
            try {
                File file = romFile();
                valid = file.isFile() && file.length() == ROM_SIZE && ROM_SHA1.equals(sha1(file));
            } catch (Exception ignored) {
            }
            final boolean ok = valid;
            runOnUiThread(() -> {
                busy(false, ok ? "ROM valide et prête." : "Aucune ROM valide installée.");
                choose.setText(ok ? "Changer de ROM" : "Choisir une ROM");
                play.setVisibility(ok ? View.VISIBLE : View.GONE);
            });
        }, "RomCheck").start();
    }

    private void openPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{
                "application/octet-stream", "application/zip", "application/x-zip-compressed"});
        startActivityForResult(intent, REQUEST_ROM);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_ROM) return;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            status.setText("Sélection annulée.");
            return;
        }
        importRom(data.getData());
    }

    private void importRom(Uri uri) {
        busy(true, "Lecture et validation de la ROM…");
        play.setVisibility(View.GONE);
        new Thread(() -> {
            try {
                byte[] source = readSelected(uri);
                byte[] normalized = normalize(source);
                String hash = sha1(normalized);
                if (!ROM_SHA1.equals(hash)) {
                    throw new IOException("ROM incompatible. SHA-1 détecté : " + hash);
                }
                save(normalized, romFile());
                runOnUiThread(() -> {
                    busy(false, "ROM US Rev.00 valide.");
                    choose.setText("Changer de ROM");
                    play.setVisibility(View.VISIBLE);
                });
            } catch (Exception error) {
                runOnUiThread(() -> busy(false, "Erreur : " + message(error)));
            }
        }, "RomImport").start();
    }

    private byte[] readSelected(Uri uri) throws IOException {
        String name = displayName(uri).toLowerCase(Locale.ROOT);
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null) throw new IOException("Impossible d’ouvrir le fichier.");
            if (name.endsWith(".zip")) return readZip(in);
            if (!romExtension(name)) throw new IOException("Choisis un fichier .z64, .v64, .n64 ou .zip.");
            return readLimited(in);
        }
    }

    private byte[] readZip(InputStream input) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(input)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (!entry.isDirectory() && romExtension(entry.getName().toLowerCase(Locale.ROOT))) {
                    return readLimited(zip);
                }
                zip.closeEntry();
            }
        }
        throw new IOException("Aucune ROM compatible dans le ZIP.");
    }

    private static boolean romExtension(String name) {
        return name.endsWith(".z64") || name.endsWith(".v64") || name.endsWith(".n64");
    }

    private static byte[] readLimited(InputStream input) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(ROM_SIZE);
        byte[] buffer = new byte[65536];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) != -1) {
            total += count;
            if (total > MAX_SIZE) throw new IOException("Fichier trop volumineux.");
            out.write(buffer, 0, count);
        }
        return out.toByteArray();
    }

    private static byte[] normalize(byte[] data) throws IOException {
        if (data.length != ROM_SIZE) throw new IOException("La ROM doit faire exactement 8 Mio.");
        int a = data[0] & 255, b = data[1] & 255, c = data[2] & 255, d = data[3] & 255;
        if (a == 0x80 && b == 0x37 && c == 0x12 && d == 0x40) return data;
        byte[] out = data.clone();
        if (a == 0x37 && b == 0x80 && c == 0x40 && d == 0x12) {
            for (int i = 0; i < out.length; i += 2) {
                byte t = out[i]; out[i] = out[i + 1]; out[i + 1] = t;
            }
            return out;
        }
        if (a == 0x40 && b == 0x12 && c == 0x37 && d == 0x80) {
            for (int i = 0; i < out.length; i += 4) {
                byte x0 = out[i], x1 = out[i + 1];
                out[i] = out[i + 3]; out[i + 1] = out[i + 2];
                out[i + 2] = x1; out[i + 3] = x0;
            }
            return out;
        }
        throw new IOException("En-tête N64 invalide.");
    }

    private File romFile() {
        File base = getExternalFilesDir(null);
        if (base == null) base = getFilesDir();
        return new File(new File(base, "user"), ROM_NAME);
    }

    private static void save(byte[] data, File target) throws IOException {
        File parent = target.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("Impossible de créer le dossier de la ROM.");
        }
        File tmp = new File(parent, ROM_NAME + ".tmp");
        try (FileOutputStream out = new FileOutputStream(tmp, false)) {
            out.write(data); out.flush(); out.getFD().sync();
        }
        if (target.exists() && !target.delete()) throw new IOException("Impossible de remplacer la ROM.");
        if (!tmp.renameTo(target)) throw new IOException("Impossible d’installer la ROM.");
    }

    private void launchGame() {
        if (!romFile().isFile()) {
            status.setText("Sélectionne une ROM valide.");
            return;
        }
        startActivity(new Intent(this, sm64coopdxActivity.class));
        finish();
    }

    private void busy(boolean active, String message) {
        status.setText(message);
        progress.setVisibility(active ? View.VISIBLE : View.GONE);
        choose.setEnabled(!active);
        play.setEnabled(!active);
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(uri,
                new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) return cursor.getString(index);
            }
        } catch (Exception ignored) {
        }
        return "";
    }

    private static String sha1(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-1");
        try (InputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = in.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        return hex(digest.digest());
    }

    private static String sha1(byte[] data) throws Exception {
        return hex(MessageDigest.getInstance("SHA-1").digest(data));
    }

    private static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) out.append(String.format(Locale.ROOT, "%02x", value & 255));
        return out.toString();
    }

    private static String message(Exception error) {
        return error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
