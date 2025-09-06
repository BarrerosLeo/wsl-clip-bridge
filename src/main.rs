use std::env;
use std::fs::{self, File};
use std::io::{self, Cursor, Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, SystemTime};

use image::ImageFormat;
use image::imageops::FilterType;
use serde::Deserialize;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

#[derive(Debug)]
struct Args {
    #[allow(dead_code)] // Keep for xclip compatibility
    selection: String,
    mime_type: Option<String>,
    mode_output: bool,
    input_file: Option<String>,
}

fn parse_args() -> Args {
    let mut selection = String::from("clipboard");
    let mut mime_type: Option<String> = None;
    let mut mode_output = false;
    let mut input_file: Option<String> = None;

    let mut it = env::args().skip(1).peekable();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-selection" => {
                if let Some(val) = it.next() {
                    selection = val;
                }
            }
            "-t" => {
                if let Some(val) = it.next() {
                    mime_type = Some(val);
                }
            }
            "-o" => {
                mode_output = true;
            }
            "-i" => {
                // optional filename after -i if next isn't a flag
                if let Some(peek) = it.peek()
                    && !peek.starts_with('-')
                {
                    input_file = it.next();
                }
            }
            _ => {
                // ignore other args; compatibility shim
            }
        }
    }

    Args {
        selection,
        mime_type,
        mode_output,
        input_file,
    }
}

fn get_storage_directory() -> PathBuf {
    // For WSL, prefer ~/.cache as it's more reliable and predictable
    // WSL's /run/user/ isn't always tmpfs and may not exist

    // First try XDG_CACHE_HOME if set
    if let Ok(xdg_cache) = env::var("XDG_CACHE_HOME")
        && !xdg_cache.trim().is_empty()
    {
        return PathBuf::from(xdg_cache).join("wsl-clip-bridge");
    }

    // Use ~/.cache (most reliable for WSL)
    if let Ok(home) = env::var("HOME") {
        return PathBuf::from(home).join(".cache").join("wsl-clip-bridge");
    }

    // Fall back to /tmp with UID for isolation
    let uid = env::var("UID").unwrap_or_else(|_| "unknown".to_string());
    PathBuf::from(format!("/tmp/wsl-clip-bridge-{uid}"))
}

fn get_image_path() -> PathBuf {
    get_storage_directory().join("image.bin")
}

fn get_image_format_path() -> PathBuf {
    get_storage_directory().join("image.format")
}

fn get_text_path() -> PathBuf {
    get_storage_directory().join("text.txt")
}

fn ensure_storage_directory() -> io::Result<()> {
    let dir = get_storage_directory();
    if !dir.exists() {
        fs::create_dir_all(&dir)?;
        // restrict perms to user on unix
        #[cfg(unix)]
        {
            let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
        }
    }
    Ok(())
}

fn is_file_non_empty(path: &Path) -> bool {
    fs::metadata(path).is_ok_and(|m| m.is_file() && m.len() > 0)
}

fn print_targets() {
    let ttl = load_ttl();

    // Check for image and read its format
    let image_path = get_image_path();
    if is_file_fresh(&image_path, ttl) {
        if let Ok(format) = fs::read_to_string(get_image_format_path()) {
            let format = format.trim();
            println!("{format}");
            // Also output jpg alias for jpeg
            if format == "image/jpeg" {
                println!("image/jpg");
            }
        }
    } else if image_path.exists() {
        // Clean up expired image files
        let _ = fs::remove_file(&image_path);
        let _ = fs::remove_file(get_image_format_path());
    }

    let text_path = get_text_path();
    if is_file_fresh(&text_path, ttl) {
        println!("text/plain;charset=utf-8");
        println!("STRING");
    } else if text_path.exists() {
        // Clean up expired text file
        let _ = fs::remove_file(&text_path);
    }
}

fn output_type(mime: &str) -> io::Result<i32> {
    match mime {
        m if m.starts_with("text/plain") => {
            let text_path = get_text_path();
            let ttl = load_ttl();
            if is_file_fresh(&text_path, ttl) {
                let mut file = File::open(text_path)?;
                let mut buffer = Vec::new();
                file.read_to_end(&mut buffer)?;
                io::stdout().write_all(&buffer)?;
                Ok(0)
            } else {
                // Clean up expired file
                if text_path.exists() {
                    let _ = fs::remove_file(&text_path);
                }
                Ok(1)
            }
        }
        "image/png" | "image/jpeg" | "image/jpg" | "image/gif" | "image/webp" => {
            let image_path = get_image_path();
            let ttl = load_ttl();
            if is_file_fresh(&image_path, ttl) {
                // Check if the stored format matches what was requested
                if let Ok(stored_format) = fs::read_to_string(get_image_format_path()) {
                    let stored_format = stored_format.trim();
                    // Allow jpg as alias for jpeg
                    let matches = mime == stored_format
                        || (mime == "image/jpg" && stored_format == "image/jpeg");
                    if matches {
                        let mut file = File::open(image_path)?;
                        let mut buffer = Vec::new();
                        file.read_to_end(&mut buffer)?;
                        io::stdout().write_all(&buffer)?;
                        return Ok(0);
                    }
                }
            } else if image_path.exists() {
                // Clean up expired image files
                let _ = fs::remove_file(&image_path);
                let _ = fs::remove_file(get_image_format_path());
            }
            Ok(1)
        }
        _ => Ok(1),
    }
}

fn validate_file_access(path: &Path) -> io::Result<()> {
    // Check file size limit
    let config = load_config();
    if let Some(cfg) = config {
        // Check file size
        if let Some(max_mb) = cfg.max_file_size_mb
            && max_mb > 0
            && let Ok(metadata) = fs::metadata(path)
        {
            let max_bytes = max_mb * 1024 * 1024;
            if metadata.len() > max_bytes {
                eprintln!("Error: File exceeds maximum size of {max_mb}MB");
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "File too large",
                ));
            }
        }

        // Check path restrictions
        if let Some(restrict) = cfg.restrict_to_home
            && restrict
            && let Ok(home) = env::var("HOME")
        {
            let home_path = PathBuf::from(home);
            let canonical_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
            if !canonical_path.starts_with(&home_path) {
                eprintln!("Error: Access denied - file is outside home directory");
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "Access denied",
                ));
            }
        }

        // Check allowed directories
        if let Some(allowed_dirs) = cfg.allowed_directories
            && !allowed_dirs.is_empty()
        {
            let canonical_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
            let mut is_allowed = false;
            for dir in &allowed_dirs {
                let allowed_path = PathBuf::from(dir);
                if canonical_path.starts_with(&allowed_path) {
                    is_allowed = true;
                    break;
                }
            }
            if !is_allowed {
                eprintln!("Error: File is not in an allowed directory");
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "Access denied",
                ));
            }
        }
    }
    Ok(())
}

#[allow(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss
)]
fn downscale_image_if_needed(data: &[u8], mime: &str, max_dim: Option<u32>) -> Vec<u8> {
    // If no max dimension configured, return original
    let max_dim = match max_dim {
        Some(d) if d > 0 => d,
        _ => return data.to_vec(),
    };

    // Try to load the image
    let Ok(img) = image::load_from_memory(data) else {
        return data.to_vec(); // If can't load, return original
    };

    let (width, height) = (img.width(), img.height());
    let max_current = width.max(height);

    // Only downscale if exceeds max dimension
    if max_current <= max_dim {
        return data.to_vec();
    }

    // Calculate new dimensions preserving aspect ratio
    let scale = max_dim as f32 / max_current as f32;
    let new_width = (width as f32 * scale) as u32;
    let new_height = (height as f32 * scale) as u32;

    // Resize using Lanczos3 (best quality for screenshots with text)
    let resized = img.resize_exact(new_width, new_height, FilterType::Lanczos3);

    // Encode back to original format
    let format = match mime {
        "image/png" => ImageFormat::Png,
        "image/jpeg" | "image/jpg" => ImageFormat::Jpeg,
        "image/gif" => ImageFormat::Gif,
        "image/webp" => ImageFormat::WebP,
        _ => return data.to_vec(), // Unknown format, return original
    };

    let mut output = Cursor::new(Vec::new());
    if resized.write_to(&mut output, format).is_err() {
        return data.to_vec(); // If encoding fails, return original
    }

    output.into_inner()
}

#[allow(clippy::too_many_lines)]
fn input_type(mime: &str, file: Option<&String>) -> io::Result<i32> {
    ensure_storage_directory()?;
    match mime {
        m if m.starts_with("text/plain") => {
            let text_path = get_text_path();
            if let Some(path_str) = file {
                let path = Path::new(path_str);
                validate_file_access(path)?;
                fs::copy(path, &text_path)?;
            } else {
                let mut buffer = Vec::new();
                io::stdin().read_to_end(&mut buffer)?;
                let mut file = File::create(&text_path)?;
                file.write_all(&buffer)?;
            }
            // restrict perms to user on unix
            #[cfg(unix)]
            {
                let _ = fs::set_permissions(&text_path, fs::Permissions::from_mode(0o600));
            }
            Ok(0)
        }
        "image/png" | "image/jpeg" | "image/jpg" | "image/gif" | "image/webp" => {
            let image_path = get_image_path();
            let format_path = get_image_format_path();

            // Read the image data
            let mut img_data = Vec::new();
            if let Some(path_str) = file {
                let path = Path::new(path_str);
                validate_file_access(path)?;
                let mut f = File::open(path)?;
                f.read_to_end(&mut img_data)?;
            } else {
                // Check stdin size limit
                let config = load_config();
                let max_bytes = config
                    .and_then(|c| c.max_file_size_mb)
                    .map_or(100 * 1024 * 1024, |mb| mb * 1024 * 1024); // Default 100MB

                let mut limited_reader = io::stdin().take(max_bytes + 1);
                limited_reader.read_to_end(&mut img_data)?;

                if img_data.len() > max_bytes.try_into().unwrap_or(usize::MAX) {
                    eprintln!("Error: Input exceeds maximum size");
                    return Ok(1);
                }
            }

            // Optionally downscale based on config
            let config = load_config();
            let max_dim = config.and_then(|c| c.max_image_dimension);
            let processed_data = downscale_image_if_needed(&img_data, mime, max_dim);

            // Write the (possibly downscaled) image
            let mut file = File::create(&image_path)?;
            file.write_all(&processed_data)?;

            // Store the format (normalize jpg to jpeg)
            let format = if mime == "image/jpg" {
                "image/jpeg"
            } else {
                mime
            };
            fs::write(&format_path, format)?;

            #[cfg(unix)]
            {
                let _ = fs::set_permissions(&image_path, fs::Permissions::from_mode(0o600));
                let _ = fs::set_permissions(&format_path, fs::Permissions::from_mode(0o600));
            }
            Ok(0)
        }
        _ => {
            // Reject unsupported formats
            eprintln!(
                "Error: Unsupported format '{mime}'. Only PNG, JPEG, GIF, and WebP are supported."
            );
            Ok(1)
        }
    }
}

fn main() -> ExitCode {
    let args = parse_args();

    // TARGETS or default when output mode w/o type
    if args.mode_output {
        let code = match args.mime_type.as_deref() {
            None | Some("TARGETS") => {
                print_targets();
                0
            }
            Some(m) => output_type(m).unwrap_or(1),
        };
        return ExitCode::from(code.try_into().unwrap_or(1));
    }

    // input mode: default type to text/plain if none provided
    let mime = args.mime_type.as_deref().unwrap_or("text/plain");
    let code = input_type(mime, args.input_file.as_ref()).unwrap_or(1);
    ExitCode::from(code.try_into().unwrap_or(1))
}

// Config & TTL handling
#[derive(Debug, Deserialize, Default)]
struct BridgeConfig {
    #[serde(default)]
    ttl_secs: Option<u64>,
    #[serde(default)]
    max_image_dimension: Option<u32>,
    #[serde(default)]
    max_file_size_mb: Option<u64>,
    #[serde(default)]
    restrict_to_home: Option<bool>,
    #[serde(default)]
    allowed_directories: Option<Vec<String>>,
}

fn config_dir() -> PathBuf {
    if let Ok(xdg) = env::var("XDG_CONFIG_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg).join("wsl-clip-bridge");
    }
    env::var("HOME").map_or_else(
        |_| PathBuf::from("/tmp").join("wsl-clip-bridge"),
        |h| PathBuf::from(h).join(".config").join("wsl-clip-bridge"),
    )
}

fn config_path() -> PathBuf {
    if let Ok(p) = env::var("WSL_CLIP_BRIDGE_CONFIG")
        && !p.trim().is_empty()
    {
        return PathBuf::from(p);
    }
    config_dir().join("config.toml")
}

fn load_config() -> Option<BridgeConfig> {
    let path = config_path();
    if !path.exists() {
        // attempt to create default config file
        if let Some(dir) = path.parent() {
            let _ = fs::create_dir_all(dir);
            #[cfg(unix)]
            {
                let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
            }
        }
        let default = "# wsl-clip-bridge config\n\n# TTL for primed data in seconds (default 300)\nttl_secs = 300\n\n# Maximum image dimension in pixels (images larger will be downscaled)\n# Recommended: 1568 for optimal Claude API performance\n# Set to 0 to disable downscaling\nmax_image_dimension = 1568\n\n# Security Settings\n\n# Maximum file size in MB (default 100MB)\nmax_file_size_mb = 100\n\n# Restrict file access to home directory only (recommended)\nrestrict_to_home = true\n\n# Optional: Only allow files from specific directories\n# Uncomment and customize for ShareX-only mode:\n# allowed_directories = [\n#   \"/mnt/c/Users/YOUR_USERNAME/Pictures/ShareX\",\n#   \"/mnt/c/Users/YOUR_USERNAME/Documents/ShareX\",\n#   \"/tmp\"\n# ]\n";
        let _ = fs::write(&path, default);
        #[cfg(unix)]
        {
            let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
        }
        return None;
    }
    fs::read_to_string(&path)
        .ok()
        .and_then(|s| toml::from_str::<BridgeConfig>(&s).ok())
}

fn load_ttl() -> Duration {
    // Env var override in seconds
    if let Ok(v) = env::var("WSL_CLIP_BRIDGE_TTL_SECS")
        && let Ok(secs) = v.trim().parse::<u64>()
    {
        return Duration::from_secs(secs.min(86_400));
    }
    // TOML config: $XDG_CONFIG_HOME/wsl-clip-bridge/config.toml
    if let Some(cfg) = load_config()
        && let Some(secs) = cfg.ttl_secs
    {
        return Duration::from_secs(secs.min(86_400));
    }
    // default 5 minutes
    Duration::from_secs(300)
}

fn is_file_fresh(path: &Path, ttl: Duration) -> bool {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .is_ok_and(|modified_time| {
            SystemTime::now()
                .duration_since(modified_time)
                .is_ok_and(|elapsed| elapsed <= ttl && is_file_non_empty(path))
        })
}
