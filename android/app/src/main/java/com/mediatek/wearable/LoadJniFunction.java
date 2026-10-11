package com.mediatek.wearable;

public class LoadJniFunction {
    private static final String LIB_NAME = "Command";

    public static final int CMD_DATA = 1;
    public static final int CMD_SYNC = 2;
    public static final int CMD_MAPX = 3;
    public static final int CMD_MAPD = 4;
    public static final int CMD_CAPC = 5;
    public static final int CMD_MREE = 8;
    public static final int CMD_EXCD = 9;

    private static LoadJniFunction instance;

    static {
        System.loadLibrary(LIB_NAME);
    }

    public static synchronized LoadJniFunction a() {
        if (instance == null) {
            instance = new LoadJniFunction();
        }
        return instance;
    }

    public int b(byte[] bArr, int i3) {
        return getCmdTypeFromJni(bArr, i3);
    }

    public int c(byte[] bArr, int i3) {
        return getDataLenthFromJni(bArr, i3);
    }

    public byte[] d(int i3, String str) {
        return getDataCmdFromJni(i3, str);
    }

    public int e(byte[] bArr, int i3) {
        return setKeyFromJni(bArr, i3);
    }

    public native int getCmdTypeFromJni(byte[] bArr, int i3);
    public native byte[] getDataCmdFromJni(int i3, String str);
    public native int getDataLenthFromJni(byte[] bArr, int i3);
    public native int setKeyFromJni(byte[] bArr, int i3);
}