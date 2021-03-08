@echo off
set /p ver=Release version: 
cd ..
git tag -d v%ver%
git tag v%ver%
git push origin v%ver%