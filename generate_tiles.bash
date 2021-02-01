pattern="!(track_*|island_40_*|island_33_multi_tile_01|island_3|seabed_island|ice_shelf_+([0-9])|*_instances|blank|*_test).xml"

cd "/c/Program Files (x86)/Steam/steamapps/common/Stormworks/rom/data/tiles"
shopt -s extglob
ls $pattern
tiles=$(ls $pattern | xargs -n1000 -d " ")
locs=$(echo "$tiles" | awk '{print "			<l id=\""NR"\" tile=\"data/tiles/"$1"\" name=\"\" is_env_mod=\"false\" env_mod_spawn_num=\"1\"/>"}')
cd - > /dev/null
out_base=$(cat playlist_template.xml)
printf "$out_base" $(($(echo -e $tiles | wc -w)+1)) "$locs" > playlist.xml