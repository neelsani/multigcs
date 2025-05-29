const std = @import("std");

const ExVersion = enum {
    sdl1,
    sdl2,
    glesx11,
    console,
};

const Options = struct {
    opencv: bool = false,
    aprs: bool = false,
    wifibc: bool = false,
    v4l: bool = false,
    vlc: bool = false,
    dpf: bool = false,
};

fn getDefaultOpts(ver: ExVersion) Options {
    return switch (ver) {
        .sdl1 => .{ .aprs = true },
        .sdl2 => .{ .opencv = true },
        .console => .{ .aprs = true },
        .glesx11 => .{},
    };
}
const BuildConfig = struct {
    name: []const u8,
    version: ExVersion,
};
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const base_dir = "/usr/share/multigcs";

    const use_opencv = b.option(bool, "opencv", "Enable OpenCV support");
    const use_aprs = b.option(bool, "aprs", "Enable APRS support");
    const use_wifibc = b.option(bool, "wifibc", "Enable WiFi broadcast support");
    const use_v4l = b.option(bool, "v4l", "Enable Video4Linux support");
    const use_vlc = b.option(bool, "vlc", "Enable VLC support");
    const use_dpf = b.option(bool, "dpf", "Enable DPF display support");

    switch (target.result.os.tag) {
        .linux => {
            var default_step_deps = std.ArrayList(*std.Build.Step).init(b.allocator);

            for (std.meta.tags(ExVersion)) |config| {
                const defaults = getDefaultOpts(config);
                const exe = createGcsExecutable(b, .{
                    .target = target,
                    .optimize = optimize,
                    .base_dir = base_dir,
                    .opts = .{
                        .opencv = use_opencv orelse defaults.opencv,
                        .aprs = use_aprs orelse defaults.aprs,
                        .wifibc = use_wifibc orelse defaults.wifibc,
                        .v4l = use_v4l orelse defaults.v4l,
                        .vlc = use_vlc orelse defaults.vlc,
                        .dpf = use_dpf orelse defaults.dpf,
                    },
                    .config = config,
                });

                const step = b.step(@tagName(config), b.fmt("Build with {s}", .{@tagName(config)}));
                step.dependOn(&b.addInstallArtifact(exe, .{}).step);
                default_step_deps.append(&b.addInstallArtifact(exe, .{}).step) catch unreachable;
            }

            for (default_step_deps.items) |dep| {
                b.default_step.dependOn(dep);
            }
        },
        else => unreachable,
    }
}

fn createGcsExecutable(
    b: *std.Build,
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        base_dir: []const u8,
        opts: Options,
        config: ExVersion,
    },
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = b.fmt("gcs-{s}", .{@tagName(options.config)}),
        .target = options.target,
        .optimize = options.optimize,
    });
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

    // Add all base source files
    exe.addCSourceFiles(.{
        .files = &(gcs_sources),
        .flags = &[_][]const u8{
            "-O3",
            "-Wall",
            "-ggdb",
            "-Wno-address-of-packed-member",
            "-Wno-unused-variable",
            "-Wno-unused-but-set-variable",
            "-w",
        },
    });

    // Add conditional source files (same as before)
    if (options.opts.aprs) {
        exe.addCSourceFile(.{
            .file = b.path("aprs.c"),
            .flags = &[_][]const u8{ "-O3", "-Wall", "-ggdb", "-w" },
        });
        exe.root_module.addCMacro("USE_APRS", "");
    }

    if (options.opts.wifibc) {
        const wifibc_sources = [_][]const u8{
            "wifibc/wifibc.c",
            "wifibc/lib.c",
            "wifibc/radiotap.c",
            "wifibc/fec.c",
        };
        exe.addCSourceFiles(.{
            .files = &wifibc_sources,
            .flags = &[_][]const u8{
                "-O3",
                "-Wall",
                "-ggdb",
                "-w",
            },
        });
        exe.root_module.addCMacro("USE_WIFIBC", "");
        exe.addIncludePath(b.path("wifibc"));
        exe.linkSystemLibrary("rt");
        exe.linkSystemLibrary("pcap");
        exe.linkSystemLibrary("avformat");
        exe.linkSystemLibrary("avcodec");
        exe.linkSystemLibrary("swscale");
        exe.linkSystemLibrary("avutil");
    }
    if (options.opts.v4l) {
        exe.root_module.addCMacro("USE_V4L", "");
    }

    if (options.opts.vlc) {
        exe.addCSourceFile(.{
            .file = b.path("draw/vlcinput.c"),
            .flags = &[_][]const u8{ "-O3", "-Wall", "-ggdb", "-w" },
        });
        exe.root_module.addCMacro("USE_V4L", "");
        exe.linkSystemLibrary("vlc");
    }

    if (options.opts.dpf) {
        const dpf_sources = [_][]const u8{
            "dpf/display_dpf.c",
            "dpf/dpflib.c",
            "dpf/rawusb.c",
        };
        exe.addCSourceFiles(.{
            .files = &dpf_sources,
            .flags = &[_][]const u8{ "-O3", "-Wall", "-ggdb", "-w" },
        });
        exe.root_module.addCMacro("DPF_DISPLAY", "");
        exe.linkSystemLibrary("usb");
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
    switch (options.config) {
        .sdl1 => {
            exe.linkSystemLibrary("SDL");
            exe.linkSystemLibrary("SDL_image");
            exe.linkSystemLibrary("SDL_net");
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("GLU");
            exe.linkSystemLibrary("GLEW");
            exe.addIncludePath(b.path("quirc"));
            // Common sources
            const common_sources = [_][]const u8{
                "draw/opencv.c",
                "quirc/decode.c",
                "quirc/identify.c",
                "quirc/quirc.c",
                "quirc/version_db.c",
                "quirc/qrcheck.c",
            };

            // Extra objects
            const extra_sources = [_][]const u8{
                "draw/gl_draw.c",
            };

            exe.addCSourceFiles(.{
                .files = &(common_sources ++ extra_sources),
                .flags = &[_][]const u8{
                    "-O3",
                    "-Wall",
                    "-ggdb",
                    "-Wno-address-of-packed-member",
                    "-Wno-unused-variable",
                    "-Wno-unused-but-set-variable",
                    "-w",
                },
            });

            exe.root_module.addCMacro("SDLGL", "");
            exe.root_module.addCMacro("BASE_DIR", b.fmt("\"{s}\"", .{options.base_dir}));
        },
        .sdl2 => {
            // Common sources
            const common_sources = [_][]const u8{
                "draw/opencv.c",
            };
            // Extra objects
            const extra_sources = [_][]const u8{
                "draw/gl_draw.c",
            };

            exe.addCSourceFiles(.{
                .files = &(common_sources ++ extra_sources),
                .flags = &[_][]const u8{
                    "-O3",
                    "-Wall",
                    "-ggdb",
                    "-Wno-address-of-packed-member",
                    "-Wno-unused-variable",
                    "-Wno-unused-but-set-variable",
                    "-w",
                },
            });
            //const SDL2 = b.dependency("SDL2", .{ .target = options.target, .optimize = options.optimize });
            //exe.linkLibrary(SDL2.artifact("SDL2"));
            exe.linkSystemLibrary("SDL2");

            //const SDL2_image = b.dependency("SDL2_image", .{ .target = options.target, .optimize = options.optimize });
            //exe.linkLibrary(SDL2_image.artifact("SDL2_image"));
            exe.linkSystemLibrary("SDL2_image");
            exe.linkSystemLibrary("SDL2_net");
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("GLU");
            exe.linkSystemLibrary("GLEW");
            exe.root_module.addCMacro("SDL2", "");
            exe.root_module.addCMacro("SDLGL", "");
            exe.root_module.addCMacro("BASE_DIR", b.fmt("\"{s}\"", .{options.base_dir}));
        },
        .glesx11 => {
            exe.linkSystemLibrary("SDL");
            exe.linkSystemLibrary("SDL_image");
            exe.linkSystemLibrary("SDL_net");
            exe.linkSystemLibrary("EGL");
            exe.linkSystemLibrary("GLESv2");
            // Common sources
            const common_sources = [_][]const u8{
                "Common/esShader.c",
                "Common/esTransform.c",
                "Common/esShapes.c",
                "Common/esUtil.c",
            };
            // Extra objects
            const extra_sources = [_][]const u8{
                "draw/gles_draw.c",
            };

            exe.addCSourceFiles(.{
                .files = &(common_sources ++ extra_sources),
                .flags = &[_][]const u8{
                    "-O3",
                    "-Wall",
                    "-ggdb",
                    "-Wno-address-of-packed-member",
                    "-Wno-unused-variable",
                    "-Wno-unused-but-set-variable",
                    "-w",
                },
            });

            exe.root_module.addCMacro("MESA", "");
            exe.root_module.addCMacro("BASE_DIR", b.fmt("\"{s}\"", .{options.base_dir}));
        },
        .console => {
            exe.linkSystemLibrary("SDL");
            exe.linkSystemLibrary("SDL_image");
            exe.linkSystemLibrary("SDL_net");
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("GLU");
            exe.linkSystemLibrary("GLEW");
            exe.addIncludePath(b.path("quirc"));
            // Common sources
            const common_sources = [_][]const u8{
                "draw/opencv.c",
                "quirc/decode.c",
                "quirc/identify.c",
                "quirc/quirc.c",
                "quirc/version_db.c",
                "quirc/qrcheck.c",
            };

            // Extra objects
            const extra_sources = [_][]const u8{
                "draw/gl_draw.c",
            };

            exe.addCSourceFiles(.{
                .files = &(common_sources ++ extra_sources),
                .flags = &[_][]const u8{
                    "-O3",
                    "-Wall",
                    "-ggdb",
                    "-Wno-address-of-packed-member",
                    "-Wno-unused-variable",
                    "-Wno-unused-but-set-variable",
                    "-w",
                },
            });

            exe.root_module.addCMacro("SDLGL", "");
            exe.root_module.addCMacro("BASE_DIR", b.fmt("\"{s}\"", .{options.base_dir}));
            exe.root_module.addCMacro("CONSOLE_ONLY", "");
            exe.root_module.addCMacro("HTML_DRAWING", "");
        },
    }

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
    if (options.opts.opencv) {
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
