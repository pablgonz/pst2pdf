--[[
   ** Build config for pst2pdf using l3build **
--]]

-- Identification
module  = "pst2pdf"
scriptv = "0.21"
scriptd = "2020-09-22"
ctanpkg = module
ctanzip = ctanpkg.."-"..scriptv

-- Configuration of files for build and installation
maindir     = "."
textfiledir = "."
textfiles   = {"Changes","README.md"}
docfiledir  = "./doc"
docfiles    = {
  "pst2pdf-doc.tex",
  "test1-pdf.pdf",
  "test2-pdf.pdf",
  "test3-pdf.pdf",
  "test1.tex",
  "test2.tex",
  "test3.tex",
  "tux.jpg",
}

bibfiles      = {"pst2pdf-doc.bib"}
sourcefiledir = "./script"
sourcefiles   = {"pst2pdf-doc.tex","Changes","pst2pdf.pl"}
installfiles  = {"*.*"}
scriptfiles   = {"*.pl"}
tdslocations  = {
  "doc/support/pst2pdf/pst2pdf-doc.pdf",
  "doc/support/pst2pdf/pst2pdf-doc.tex",
  "doc/support/pst2pdf/pst2pdf-doc.bib",
  "doc/support/pst2pdf/test1.tex",
  "doc/support/pst2pdf/test2.tex",
  "doc/support/pst2pdf/test3.tex",
  "doc/support/pst2pdf/test1-pdf.pdf",
  "doc/support/pst2pdf/test2-pdf.pdf",
  "doc/support/pst2pdf/test3-pdf.pdf",
  "doc/support/pst2pdf/tux.jpg",
  "doc/support/pst2pdf/README.md",
  "doc/support/pst2pdf/Changes",
  "scripts/pst2pdf/pst2pdf.pl",
}

-- Clean files
cleanfiles = {
  ctanzip..".curlopt",
  ctanzip..".zip",
}

flatten = false
packtdszip = false

-- Update date and version
tagfiles = {"pst2pdf-doc.tex", "README.md","pst2pdf.pl"}

function update_tag(file, content, tagname, tagdate)
  if string.match(file, "%.tex$") then
    content = string.gsub(content,
                          "\\def\\fileversion{.-}",
                          "\\def\\fileversion{"..scriptv.."}")
    content = string.gsub(content,
                          "\\def\\filedate{.-}",
                          "\\def\\filedate{"..scriptd.."}")
  end
  if string.match(file, "README.md$") then
    content = string.gsub(content,
                          "Release v%d+.%d+%a* \\%[%d%d%d%d%-%d%d%-%d%d\\%]",
                          "Release v"..scriptv.." \\["..scriptd.."\\]")
  end
  if string.match(file, "pst2pdf.pl$") then
    local scriptd = string.gsub(scriptd, "/", "-")
    local scriptv = "v"..scriptv
    content = string.gsub(content,
                          "# v%d+.%d+%a* %d%d%d%d%-%d%d%-%d%d (.-)",
                          "# "..scriptv.." "..scriptd.." %1")
    content = string.gsub(content,
                          "(my %$date %s* = ')(.-)';",
                          "%1"..scriptd.."';")
    content = string.gsub(content,
                          "(my %$nv %s* = ')(.-)';",
                          "%1"..scriptv.."';")
  end
  return content
end

-- Line length in 80 characters
local function os_message(text)
  local mymax = 77 - string.len(text) - string.len("done")
  local msg = text.." "..string.rep(".", mymax).." done"
  return print(msg)
end

-- Create check_marked_tags() function
local function check_marked_tags()
  local f = assert(io.open("doc/pst2pdf-doc.tex", "r"))
  marked_tags = f:read("*all")
  f:close()
  local m_docv = string.match(marked_tags, "\\def\\fileversion{(.-)}")
  local m_docd = string.match(marked_tags, "\\def\\filedate{(.-)}")

  if scriptv == m_docv and scriptd == m_docd then
    os_message("Checking version and date in pst2pdf-doc.tex")
  else
    print("** Warning: pst2pdf-doc.tex is marked with version "..m_docv.." and date "..m_docd)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
  end
end

-- Create check_script_tags() function
local function check_script_tags()
  local scriptv = "v"..scriptv

  local f = assert(io.open("script/pst2pdf.pl", "r"))
  script_tags = f:read("*all")
  f:close()
  local m_scriptd = string.match(script_tags, "my %$date %s* = '(.-)';")
  local m_scriptv = string.match(script_tags, "my %$nv %s* = '(.-)';")

  if scriptv == m_scriptv and scriptd == m_scriptd then
    os_message("Checking version and date in pst2pdf.pl")
  else
    print("** Warning: pst2pdf.pl is marked with version "..m_scriptv.." and date "..m_scriptd)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
  end
end

-- Create check_readme_tags() function
local function check_readme_tags()
  local scriptv = "v"..scriptv

  local f = assert(io.open("./README.md", "r"))
  readme_tags = f:read("*all")
  f:close()
  local m_readmev, m_readmed = string.match(readme_tags, "Release (v%d+.%d+%a*) \\%[(%d%d%d%d%-%d%d%-%d%d)\\%]")

  if scriptv == m_readmev and scriptd == m_readmed then
    os_message("Checking version and date in README.md")
  else
    print("** Warning: README.md is marked with version "..m_readmev.." and date "..m_readmed)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
  end
end

-- Config tag_hook
function tag_hook(tagname)
  check_readme_tags()
  check_marked_tags()
  check_script_tags()
end

-- Add "tagged" target to l3build CLI
if options["target"] == "tagged" then
  check_readme_tags()
  check_marked_tags()
  check_script_tags()
  os.exit()
end

-- Generating documentation
typesetfiles  = {"pst2pdf-doc.tex"}
biberopts     = "-q"

function typeset(file)
  local file = jobname(docfiledir.."/pst2pdf-doc.tex")
  -- xelatex
  print("** Running: xelatex -interaction=batchmode "..file..".tex")
  errorlevel = run(typesetdir, "xelatex -interaction=batchmode "..file..".tex >"..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: xelatex -interaction=batchmode "..file..".tex")
    return errorlevel
  end
  -- biber
  print("** Running: biber -q "..file..".bfc")
  errorlevel = biber(file, typesetdir)
  if errorlevel ~= 0 then
    error("** Error!!: biber -q "..file..".bfc")
    return errorlevel
  end
  -- index
  print("** Running: makeindex -q "..file..".idx")
  errorlevel = run(typesetdir, "makeindex -q "..file..".idx >"..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: makeindex -q "..file..".idx")
    return errorlevel
  end
  -- xelatex second run
  print("** Running: xelatex -interaction=batchmode "..file..".tex")
  errorlevel = run(typesetdir, "xelatex -interaction=batchmode "..file..".tex >"..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: xelatex -interaction=batchmode "..file..".tex")
    return errorlevel
  end
  -- xelatex third run
  print("** Running: xelatex -interaction=batchmode "..file..".tex")
  errorlevel = run(typesetdir, "xelatex -interaction=batchmode "..file..".tex >"..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: xelatex -interaction=batchmode "..file..".tex")
    return errorlevel
  end
  return 0
end

-- Create make_tmp_dir() function
local function make_tmp_dir()
  -- Fix basename(path) in windows
  local function basename(path)
    return path:match("^.*[\\/]([^/\\]*)$")
  end
  local tmpname = os.tmpname()
  tmpdir = basename(tmpname)
  errorlevel = mkdir(tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: The ./"..tmpdir.." directory could not be created")
    return errorlevel
  else
    os_message("Creating the temporary directory ./"..tmpdir)
  end
  return 0
end

-- Add "testpkg" target to l3build CLI
if options["target"] == "testpkg" then
  -- Check tags
  check_readme_tags()
  check_marked_tags()
  check_script_tags()
  -- Create a tmp dir
  make_tmp_dir()
  -- Copy script
  local pst2pdf = "pst2pdf.pl"
  errorlevel = cp(pst2pdf, sourcefiledir, tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy "..pst2pdf.." from "..sourcefiledir.." to ./"..tmpdir)
    return errorlevel
  else
    os_message("Copying "..pst2pdf.." from "..sourcefiledir.." to ./"..tmpdir)
  end
  -- Check syntax
  print("** Running: perl -cw "..pst2pdf)
  errorlevel = run(tmpdir, "perl -cw "..pst2pdf)
  if errorlevel ~= 0 then
    error("** Error!!: perl -cw "..pst2pdf)
    return errorlevel
  end
  -- Copy test files
  errorlevel = ( cp("test1.tex", "./doc", tmpdir) + cp("test2.tex", "./doc", tmpdir)
               + cp("test3.tex", "./doc", tmpdir) + cp("tux.jpg", "./doc", tmpdir))
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy test files from ./doc to /"..tmpdir)
    return errorlevel
  else
    os_message("Copying test files from ./doc to ./"..tmpdir)
  end
  -- Run a first test
  print("** Running: perl "..pst2pdf.." --noprew --log test1.tex")
  errorlevel = run(tmpdir, "perl "..pst2pdf.." --noprew --log test1.tex > "..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: perl "..pst2pdf.." --noprew --log test1.tex")
    return errorlevel
  end
  -- Run a second test
  print("** Running: perl "..pst2pdf.." --luatex --noprew --log test2.tex")
  errorlevel = run(tmpdir, "perl "..pst2pdf.." --luatex --noprew --log test2.tex > "..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: perl "..pst2pdf.." --luatex --noprew --log test2.tex")
    return errorlevel
  end
  -- Run a third test
  print("** Running: perl "..pst2pdf.." --xetex --log test3.tex")
  errorlevel = run(tmpdir, "perl "..pst2pdf.." --xetex --log test3.tex > "..os_null)
  if errorlevel ~= 0 then
    error("** Error!!: perl "..pst2pdf.." --xetex --log test3.tex")
    return errorlevel
  end
  -- Update .pdf samples in ./doc
  errorlevel = cp("*.pdf", tmpdir, "./doc")
  if errorlevel ~= 0 then
    error("** Error!!: Can't updating pdf sample files in ./doc")
    return errorlevel
  else
    os_message("Updating pdf sample files in ./doc")
  end
  -- If are OK then remove ./temp dir
  cleandir(tmpdir.."/images")
  cleandir(tmpdir)
  lfs.rmdir(tmpdir.."/images")
  lfs.rmdir(tmpdir)
  os_message("Remove temporary directory ./"..tmpdir)
  os.exit()
end
