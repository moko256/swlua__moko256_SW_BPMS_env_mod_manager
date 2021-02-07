#!/bin/sh

gen_workshop_markup()
{
	awk '
	$0 !~ /<!DOCTYPE html>/&&
	$0 !~ /.*<.{0,1}html.*>.*/&&
	$0 !~ /.*<.{0,1}body>.*/&&
	$0 !~ /.*<.{0,1}pre>.*/{
		gsub("<ul>", "[list]")
		gsub("</ul>", "[/list]")
		gsub("<ol>", "[olist]")
		gsub("</ol>", "[/olist]")
		gsub("<li>", "[*]")
		gsub("</li>", "")
		gsub("<", "[")
		gsub(">", "]")
		print
	}' ../docs/description_$1.html \
	> ../out/workshop_$1.txt
}

gen_workshop_markup "en"
gen_workshop_markup "ja"
