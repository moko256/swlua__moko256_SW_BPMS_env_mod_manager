cd "/c/Program Files (x86)/Steam/steamapps/common/Stormworks/rom/data/tiles"
shopt -s extglob
ls !(track_*|*_instances|blank|*_test).xml
tiles=$(ls !(track_*|*_instances|blank|*_test).xml | xargs -n1000 -d " ")
locs=$(echo "$tiles" | awk '{print "			<l id=\""NR"\" tile=\"data/tiles/"$1"\" name=\"\" is_env_mod=\"false\" env_mod_spawn_num=\"1\"/>"}')
cd - > /dev/null
out_base=$(cat playlist_template.xml)
printf "$out_base" $(($(echo -e $tiles | wc -w)+1)) "$locs" > playlist.xml