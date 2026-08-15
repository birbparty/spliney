local runtime = os.getenv('RIVE_RUNTIME_PATH')
if runtime == nil or runtime == '' then
    error('RIVE_RUNTIME_PATH must point at the pinned rive-runtime checkout')
end

dofile(runtime .. '/build/rive_build_config.lua')
RIVE_RUNTIME_DIR = runtime
dofile(runtime .. '/premake5_v2.lua')

project('rive_cg_renderer')
do
    kind('StaticLib')
    includedirs({ runtime .. '/include', runtime .. '/cg_renderer/include' })
    files({ runtime .. '/cg_renderer/src/**.cpp' })
    fatalwarnings({ 'All' })
end

project('rive_oracle_probe')
do
    kind('ConsoleApp')
    includedirs({ runtime .. '/include', runtime .. '/cg_renderer/include' })
    files({ 'main.cpp' })
    links({
        'rive',
        'rive_cg_renderer',
        'CoreFoundation.framework',
        'CoreGraphics.framework',
        'ImageIO.framework',
    })
    buildoptions({ '-Wno-deprecated-declarations' })
end
