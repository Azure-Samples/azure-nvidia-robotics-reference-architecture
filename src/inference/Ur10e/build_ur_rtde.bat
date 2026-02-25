@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat" x64
set CMAKE_GENERATOR=Ninja
set CMAKE_GENERATOR_PLATFORM=
set Platform=

REM Point cmake to vcpkg-installed Boost
set VCPKG_PREFIX=%~dp0temp_vcpkg_clone\installed\x64-windows-static
set BOOST_ROOT=%VCPKG_PREFIX%
set CMAKE_PREFIX_PATH=%VCPKG_PREFIX%

echo CMAKE_GENERATOR=%CMAKE_GENERATOR%
echo BOOST_ROOT=%BOOST_ROOT%
echo CMAKE_PREFIX_PATH=%CMAKE_PREFIX_PATH%
where cmake
cmake --version
where ninja

REM Clean previous build artifacts
if exist temp_build\ur_rtde-1.6.2\build-setuptools rmdir /s /q temp_build\ur_rtde-1.6.2\build-setuptools

cd temp_build\ur_rtde-1.6.2
..\..\.venv\Scripts\python.exe setup.py bdist_wheel
cd ..\..
for %%f in (temp_build\ur_rtde-1.6.2\dist\*.whl) do .venv\Scripts\pip.exe install "%%f" --no-deps
