package com.mediatek.wearable;

/**
 * Small JNI adapter for WWfit's bundled MediaTek Command library.
 * The native methods intentionally stay instance methods, matching the API
 * shape found in WWfit's original LoadJniFunction class.
 */
public final class LoadJniFunction {
    private static final String LIBRARY = "Command";
    private static final LoadJniFunction INSTANCE;

    static {
        System.loadLibrary(LIBRARY);
        INSTANCE = new LoadJniFunction();
    }

    private LoadJniFunction() {}

    public static synchronized void initialize(String key) {
        byte[] bytes = key.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        INSTANCE.setKeyFromJni(bytes, bytes.length);
    }

    public static byte[] encode(int commandType, String body) {
        return INSTANCE.getDataCmdFromJni(commandType, body);
    }

    public static int inspectType(byte[] command, int length) {
        return INSTANCE.getCmdTypeFromJni(command, length);
    }

    public static int inspectDataLength(byte[] command, int length) {
        return INSTANCE.getDataLenthFromJni(command, length);
    }

    public native int getCmdTypeFromJni(byte[] bytes, int length);
    public native byte[] getDataCmdFromJni(int commandType, String body);
    public native int getDataLenthFromJni(byte[] bytes, int length);
    public native int setKeyFromJni(byte[] bytes, int length);
}
