@echo off
set /p ver=Release version: 
cd ..
git tag -d %ver%
git tag %ver%
git push origin %ver%