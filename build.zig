const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Configuration options
    const use_opencv = b.option(bool, "opencv", "Enable OpenCV support") orelse false;
    const use_aprs = b.option(bool, "aprs", "Enable APRS support") orelse true;
    const use_wifibc = b.option(bool, "wifibc", "Enable WiFi broadcast support") orelse false;
    const use_v4l = b.option(bool, "v4l", "Enable Video4Linux support") orelse false;
    const use_vlc = b.option(bool, "vlc", "Enable VLC support") orelse false;
    const use_dpf = b.option(bool, "dpf", "Enable DPF display support") orelse false;

    // Version information
    const base_dir = "/usr/share/multigcs";

    switch (target.result.os.tag) {
        .linux => {
            // SDL1 version (default)
            const sdl1_exe = createGcsExecutableLinux(b, .{
                .target = target,
                .optimize = optimize,
                .base_dir = base_dir,
                .use_opencv = use_opencv,
                .use_aprs = use_aprs,
                .use_wifibc = use_wifibc,
                .use_v4l = use_v4l,
                .use_vlc = use_vlc,
                .use_dpf = use_dpf,
                .sdl_version = .sdl1,
            });

            // SDL2 version
            const sdl2_exe = createGcsExecutableLinux(b, .{
                .target = target,
                .optimize = optimize,
                .base_dir = base_dir,
                .use_opencv = use_opencv,
                .use_aprs = use_aprs,
                .use_wifibc = use_wifibc,
                .use_v4l = use_v4l,
                .use_vlc = use_vlc,
                .use_dpf = use_dpf,
                .sdl_version = .sdl2,
            });

            // Build steps
            const sdl1_step = b.step("sdl1", "Build with SDL1");
            sdl1_step.dependOn(&b.addInstallArtifact(sdl1_exe, .{}).step);

            const sdl2_step = b.step("sdl2", "Build with SDL2");
            sdl2_step.dependOn(&b.addInstallArtifact(sdl2_exe, .{}).step);
        },
        else => {
            unreachable;
        },
    }
}

const SdlVersion = enum { sdl1, sdl2 };

fn createGcsExecutableLinux(
    b: *std.Build,
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        base_dir: []const u8,
        use_opencv: bool,
        use_aprs: bool,
        use_wifibc: bool,
        use_v4l: bool,
        use_vlc: bool,
        use_dpf: bool,
        sdl_version: SdlVersion,
    },
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = switch (options.sdl_version) {
            .sdl1 => "gcs-sdl1",
            .sdl2 => "gcs-sdl2",
        },
        .target = options.target,
        .optimize = options.optimize,
    });

    const base_dir = "/usr/share/multigcs";

    // Add C source files from GCS variable in make.inc
    const gcs_sources = [_][]const u8{
        "main.c",
        "serial.c",
        "draw/draw.c",
        "draw/videocapture.c",
        "draw/map.c",
        "geomag70.c",
        "minizip/ioapi.c",
        "minizip/unzip.c",
        "net/htmlget-wget.c",
        "screens/screen_rcflow.c",
        "screens/screen_keyboard.c",
        "screens/screen_filesystem.c",
        "screens/screen_device.c",
        "screens/screen_baud.c",
        "screens/screen_number.c",
        "screens/screen_model.c",
        "screens/screen_background.c",
        "screens/screen_wpedit.c",
        "screens/screen_hud.c",
        "screens/screen_map.c",
        "screens/screen_map_survey.c",
        "screens/screen_map_swarm.c",
        "screens/screen_calibration.c",
        "screens/screen_fms.c",
        "screens/screen_system.c",
        "screens/screen_tcl.c",
        "screens/screen_mavlink_menu.c",
        "screens/screen_tracker.c",
        "screens/screen_mwi_menu.c",
        "screens/screen_openpilot_menu.c",
        "screens/screen_videolist.c",
        "screens/screen_graph.c",
        "screens/screen_telemetry.c",
        "mavlink/my_mavlink.c",
        "mavlink/my_mavlink_rewrite.c",
        "gps/my_gps.c",
        "mwi21/mwi21.c",
        "jeti/jeti.c",
        "openpilot/openpilot.c",
        "openpilot/openpilot_xml.c",
        "frsky/frsky.c",
        "tracker/tracker.c",
        "net/savepng.c",
        "net/webserv.c",
        "net/webclient.c",
        "logging.c",
        "kml.c",
        "openpilot/uavobjects_store.c",
        "openpilot/uavobjects_encode.c",
        "openpilot/uavobjects_decode.c",
        "weather.c",
    };

    // Common sources
    const common_sources = [_][]const u8{
        "draw/opencv.c",
    };

    // Extra objects
    const extra_sources = [_][]const u8{
        "draw/gl_draw.c",
    };

    // Add all base source files
    exe.addCSourceFiles(.{
        .files = &(gcs_sources ++ common_sources ++ extra_sources),
        .flags = &[_][]const u8{
            "-DSDLGL",
            "-O3",
            "-Wall",
            "-ggdb",
            "-Wno-address-of-packed-member",
            "-Wno-unused-variable",
            "-Wno-unused-but-set-variable",
            "-w",
            b.fmt("-DBASE_DIR=\"{s}\"", .{options.base_dir}),
        },
    });

    // Add conditional source files (same as before)
    if (options.use_aprs) {
        exe.addCSourceFile(.{
            .file = b.path("aprs.c"),
            .flags = &[_][]const u8{
                "-DSDLGL",
                "-O3",
                "-Wall",
                "-ggdb",
                b.fmt("-DBASE_DIR=\"{s}\"", .{options.base_dir}),
            },
        });
    }

    if (options.use_wifibc) {
        const wifibc_sources = [_][]const u8{
            "wifibc/wifibc.c",
            "wifibc/lib.c",
            "wifibc/radiotap.c",
            "wifibc/fec.c",
        };
        exe.addCSourceFiles(.{
            .files = &wifibc_sources,
            .flags = &[_][]const u8{
                "-DSDLGL",
                "-O3",
                "-Wall",
                "-ggdb",
                b.fmt("-DBASE_DIR=\"{s}\"", .{base_dir}),
            },
        });
        exe.addIncludePath(b.path("wifibc"));
    }

    if (options.use_vlc) {
        exe.addCSourceFile(.{
            .file = b.path("draw/vlcinput.c"),
            .flags = &[_][]const u8{
                "-DSDLGL",
                "-O3",
                "-Wall",
                "-ggdb",
                b.fmt("-DBASE_DIR=\"{s}\"", .{base_dir}),
            },
        });
    }

    if (options.use_dpf) {
        const dpf_sources = [_][]const u8{
            "dpf/display_dpf.c",
            "dpf/dpflib.c",
            "dpf/rawusb.c",
        };
        exe.addCSourceFiles(.{
            .files = &dpf_sources,
            .flags = &[_][]const u8{
                "-DSDLGL",
                "-O3",
                "-Wall",
                "-ggdb",
                b.fmt("-DBASE_DIR=\"{s}\"", .{base_dir}),
            },
        });
    }

    // Add include directories
    exe.addIncludePath(b.path("."));
    exe.addIncludePath(b.path("Common"));
    exe.addIncludePath(b.path("screens"));
    exe.addIncludePath(b.path("net"));
    exe.addIncludePath(b.path("tcl"));
    exe.addIncludePath(b.path("draw"));
    exe.addIncludePath(b.path("mavlink"));
    exe.addIncludePath(b.path("gps"));
    exe.addIncludePath(b.path("mwi21"));
    exe.addIncludePath(b.path("jeti"));
    exe.addIncludePath(b.path("openpilot"));
    exe.addIncludePath(b.path("frsky"));
    exe.addIncludePath(b.path("minizip"));
    exe.addIncludePath(b.path("tracker"));
    exe.addIncludePath(b.path("utils"));

    // System libraries
    exe.linkLibC();
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("libudev");

    const libxml2 = b.dependency("libxml2", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    exe.linkLibrary(libxml2.artifact("xml"));

    // SDL and OpenGL libraries
    switch (options.sdl_version) {
        .sdl1 => {
            exe.linkSystemLibrary("SDL");
            exe.linkSystemLibrary("SDL_image");
            exe.linkSystemLibrary("SDL_net");
            exe.addIncludePath(b.path("quirc"));

            const sdl1_sources = [_][]const u8{
                "quirc/decode.c",
                "quirc/identify.c",
                "quirc/quirc.c",
                "quirc/version_db.c",
                "quirc/qrcheck.c",
            };
            exe.addCSourceFiles(.{
                .files = &sdl1_sources,
                .flags = &[_][]const u8{
                    "-DSDLGL",
                    "-O3",
                    "-Wall",
                    "-ggdb",
                    "-Wno-address-of-packed-member",
                    "-Wno-unused-variable",
                    "-Wno-unused-but-set-variable",
                    "-w",
                    b.fmt("-DBASE_DIR=\"{s}\"", .{options.base_dir}),
                },
            });
        },
        .sdl2 => {
            //const SDL2 = b.dependency("SDL2", .{ .target = options.target, .optimize = options.optimize });
            //exe.linkLibrary(SDL2.artifact("SDL2"));
            exe.linkSystemLibrary("SDL2");

            //const SDL2_image = b.dependency("SDL2_image", .{ .target = options.target, .optimize = options.optimize });
            //exe.linkLibrary(SDL2_image.artifact("SDL2_image"));
            exe.linkSystemLibrary("SDL2_image");

            exe.linkSystemLibrary("SDL2_net");
            exe.root_module.addCMacro("SDL2", "");
        },
    }
    exe.linkSystemLibrary("GL");
    exe.linkSystemLibrary("GLU");
    exe.linkSystemLibrary("GLEW");

    // XML, PNG, and other libraries
    exe.linkSystemLibrary("X11");
    exe.linkSystemLibrary("png");

    const zlib_dep = b.dependency("zlib", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    exe.linkLibrary(zlib_dep.artifact("z"));
    //exe.linkSystemLibrary("z");

    // Conditional libraries (same as before)
    if (options.use_opencv) {
        exe.linkSystemLibrary("opencv_core");
        exe.linkSystemLibrary("opencv_imgproc");
        exe.linkSystemLibrary("opencv_imgcodecs");
        exe.linkSystemLibrary("opencv_videoio");
        exe.linkSystemLibrary("opencv_objdetect");
        exe.root_module.addCMacro("USE_OPENCV", "");
        exe.root_module.addCMacro("OPENCV_EFFECTS", "");
    }

    return exe;
}

fn createInstallStep(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    install_name: []const u8,
) *std.Build.Step {
    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "/usr/bin" } },
        .dest_sub_path = install_name,
    });

    // Install wrapper script
    const install_script = b.addInstallFile(b.path("utils/gcs.sh"), "../bin/multigcs");

    // Install data files (same as before)
    const data_files = [_]struct { []const u8, []const u8 }{
        .{ "data/WMM.COF", "WMM.COF" },
        .{ "data/SRTM.list", "SRTM.list" },
        .{ "data/map-services.xml", "map-services.xml" },
        .{ "utils/clean-badmaps.sh", "clean-badmaps.sh" },
    };

    var install_step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    install_step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = b.fmt("install-{s}", .{install_name}),
        .owner = b,
    });

    install_step.dependOn(&install_exe.step);
    install_step.dependOn(&install_script.step);

    for (data_files) |file| {
        const install_data = b.addInstallFile(b.path(file[0]), b.fmt("../share/multigcs/{s}", .{file[1]}));
        install_step.dependOn(&install_data.step);
    }

    return install_step;
}
