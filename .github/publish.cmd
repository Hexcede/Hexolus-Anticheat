@echo off
set /p ver=Release version: 
cd ..
git tag %ver%
git push origin %ver%