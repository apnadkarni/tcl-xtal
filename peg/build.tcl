package require fileutil
package require pt::pgen
package require platform
package require critcl 3.3
package require critcl::app

set xtalVersion 2.0a1

set scriptDir [file normalize [file dirname [info script]]]
set libDir [file normalize [file join $scriptDir .. library]]
set genericDir [file normalize [file join $scriptDir .. generic]]

proc usage {} {
    set script [info script]
    puts "Usage:"
    puts "  $script parser   - creates the critcl and oo parsers"
    puts "  $script csource  - generates the C source for traditional build"
    puts "  $script critcl   - builds the critcl based binary extension"
    puts "  $script tea      - generates the TEA package for critcl"
    puts "  $script test     - runs tests"
    exit 1
}

set buildarea [file normalize [file join [pwd] .. build]]
set tclSources [lmap f {xtal.tcl ptast.tcl ptutil.tcl shell.tcl} {
    file join $libDir $f
}]
switch -exact -- [lindex $argv 0] {

    parser {
        set critcl_source [pt::pgen peg [fileutil::cat xtal.peg] critcl -class xtal::ParserBase -package xtal -name Xtal -version $xtalVersion]
        # We want the tcl files to be included in the package
        # so insert it into the generated critcl parser file
        fileutil::writeFile xtal.critcl [regsub {return\s*$} $critcl_source "critcl::tsources $tclSources"]
        set oo_source [pt::pgen peg [fileutil::cat xtal.peg] oo -class xtal::ParserBase -package xtal -name Xtal -version $xtalVersion]
        fileutil::writeFile [file join $libDir ooparser.tcl] $oo_source
    }

    csource {
        critcl::app::main [list -pkg -libdir [file join $buildarea lib] -includedir [file join $buildarea include] -cache [file join $buildarea cache] -keep -clean {*}[lrange $argv 1 end] xtal xtal.critcl]
        set cfiles [glob [file join $buildarea cache *.c]]
        if {[llength $cfiles] != 2} {
            error "Expected 2 C source files, got [llength $cfiles]"
        }
        if {[file size [lindex $cfiles 0]] > [file size [lindex $cfiles 1]]} {
            lassign $cfiles parserSource mainSource
        } else {
            lassign $cfiles mainSource parserSource
        }
        file copy -force $parserSource [file join $genericDir parser.c]
        set fd [open [file join $genericDir xtal.c] w]
        fileutil::foreachLine line $mainSource {
            if {[string match *Tcl_PkgRequire* $line]} {
                regsub {"\d+\.\d+"} $line TCL_VERSION line
            }
            puts $fd $line
        }
        close $fd
    }

    ext -
    extension {
        critcl::app::main [list -pkg -libdir [file join $buildarea lib] -includedir [file join $buildarea include] -cache [file join $buildarea cache] -clean {*}[lrange $argv 1 end] xtal xtal.critcl]
    }

    tea {
        critcl::app::main [list -tea -libdir [file join $buildarea tea] {*}[lrange $argv 1 end] xtal xtal.critcl]
    }

    test {
        cd ../tests
	lappend env(TCLLIBPATH); # Make sure it exists
        set env(TCLLIBPATH) [linsert $env(TCLLIBPATH) 0 [file join $buildarea lib]]
        set fd [open |[list [info nameofexecutable] all.tcl -file xtal*.test {*}[lrange $argv 1 end]]]
        while {[gets $fd line] >= 0} {
            puts $line
        }
        close $fd
    }
    default {
        usage
    }
}
