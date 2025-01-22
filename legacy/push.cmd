REM Dedicatedly for windows system where the git links do not work.
REM And it works only on the usb disk connection.

robocopy ..\koreader\ d:\koreader\ /E /XD plugins /XF *.so /XF *.so.*
robocopy . d:\koreader\ /E *.so fbink luajit sdcv tar wmctl zsync2 *.so.*
