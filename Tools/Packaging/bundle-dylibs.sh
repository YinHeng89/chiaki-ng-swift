#!/bin/zsh
set -eu

if (( $# < 2 )); then
    echo 'usage: bundle-dylibs.sh APP_DIR MACH_O...' >&2
    exit 1
fi

app_dir="$1"
shift
if [[ -d "$app_dir/Contents" ]]; then
    frameworks_dir="$app_dir/Contents/Frameworks"
    executable_dir="$app_dir/Contents/MacOS"
else
    frameworks_dir="$app_dir/Frameworks"
    executable_dir="$app_dir"
fi
mkdir -p "$frameworks_dir"

typeset -a queue
typeset -A processed
typeset -A origins
queue=("$@")

for root in "$@"; do
    origins["${root:t}"]="$(realpath "$root")"
done

while (( ${#queue[@]} > 0 )); do
    target="${queue[1]}"
    queue=("${queue[@]:1}")
    target_real="$(realpath "$target")"
    if [[ -n "${processed[$target_real]-}" ]]; then
        continue
    fi
    processed[$target_real]=1

    dependencies=("${(@f)$(otool -L "$target" | tail -n +2 | awk '{print $1}')}" )
    for dependency in "${dependencies[@]}"; do
        case "$dependency" in
            /System/Library/*|/usr/lib/*)
                continue
                ;;
        esac

        reference="$dependency"
        name="${dependency:t}"
        bundled="$frameworks_dir/$name"
        if [[ "$dependency" == @rpath/* ]]; then
            if [[ -f "$bundled" ]]; then
                continue
            fi
            target_origin="${origins[${target:t}]-$target_real}"
            dependency="${target_origin:h}/$name"
            if [[ ! -f "$dependency" ]]; then
                search_paths=("${(@f)$(otool -l "$target" | awk '/LC_RPATH/{getline; getline; print $2}')}" )
                for search_path in "${search_paths[@]}"; do
                    search_path="${search_path/#@loader_path/${target_origin:h}}"
                    if [[ -f "$search_path/$name" ]]; then
                        dependency="$search_path/$name"
                        break
                    fi
                done
            fi
        elif [[ "$dependency" == @loader_path/* ]]; then
            target_origin="${origins[${target:t}]-$target_real}"
            dependency="${target_origin:h}/${dependency#@loader_path/}"
        elif [[ "$dependency" == @executable_path/* ]]; then
            if [[ -f "$bundled" ]]; then
                continue
            fi
            dependency="$executable_dir/${dependency#@executable_path/}"
        fi

        if [[ ! -f "$dependency" ]]; then
            echo "Missing dynamic library: $dependency" >&2
            exit 1
        fi

        source_real="$(realpath "$dependency")"
        existing_origin="${origins[$name]-}"
        if [[ -n "$existing_origin" && "$existing_origin" != "$source_real" ]]; then
            echo "Dynamic library name collision: $name" >&2
            exit 1
        fi

        install_name_tool -change "$reference" "@rpath/$name" "$target"
        if [[ ! -f "$bundled" ]]; then
            cp -L "$source_real" "$bundled"
            chmod u+w "$bundled"
            install_name_tool -id "@rpath/$name" "$bundled"
            origins[$name]="$source_real"
            queue+=("$bundled")
        fi
    done
done

mach_o_files=("$executable_dir/ChiakiNG" "$frameworks_dir"/*.dylib)
for mach_o in "${mach_o_files[@]}"; do
    rpaths=("${(@f)$(otool -l "$mach_o" | awk '/LC_RPATH/{getline; getline; print $2}')}" )
    for rpath in "${rpaths[@]}"; do
        if [[ "$rpath" == /* ]]; then
            install_name_tool -delete_rpath "$rpath" "$mach_o"
        fi
    done
    unresolved="$(otool -L "$mach_o" | tail -n +2 | awk '{print $1}' | grep -E '^/' | grep -Ev '^(/System/Library/|/usr/lib/)' || true)"
    if [[ -n "$unresolved" ]]; then
        echo "Unbundled dynamic libraries in $mach_o:" >&2
        echo "$unresolved" >&2
        exit 1
    fi
    while IFS= read -r dependency; do
        if [[ "$dependency" == @rpath/* && ! -f "$frameworks_dir/${dependency:t}" ]]; then
            echo "Missing bundled rpath dependency in $mach_o: $dependency" >&2
            exit 1
        fi
    done < <(otool -L "$mach_o" | tail -n +2 | awk '{print $1}')
done
