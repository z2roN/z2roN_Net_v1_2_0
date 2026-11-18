# flutter create --platforms=windows 로 만들어진 윈도우 프로젝트에 z2roN Net 설정을 덧씌웁니다.
#  - 창 제목/크기, 프로그램 이름(파일 속성), 아이콘
import os, re, shutil, sys

app = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
runner = os.path.join(app, "windows", "runner")

# 1) main.cpp: 창 제목과 처음 크기
mc = os.path.join(runner, "main.cpp")
s = open(mc, encoding="utf-8").read()
s2 = re.sub(r'(window\.Create\()L"[^"]*"(\s*,\s*origin\s*,\s*size\))', r'\1L"z2roN Net"\2', s)
s2 = re.sub(r"Win32Window::Size\s+size\(\s*\d+\s*,\s*\d+\s*\)", "Win32Window::Size size(720, 920)", s2)
open(mc, "w", encoding="utf-8").write(s2)
print("main.cpp", "changed" if s2 != s else "UNCHANGED (확인 필요)")

# 2) Runner.rc: 파일 속성의 이름 (없으면 건너뜀)
rc = os.path.join(runner, "Runner.rc")
if os.path.exists(rc):
    raw = open(rc, "rb").read()
    txt = raw.decode("utf-8", errors="ignore")
    t2 = re.sub(r'(VALUE "(?:FileDescription|ProductName|InternalName)",\s*)"[^"]*"', r'\1"z2roN Net"', txt)
    open(rc, "wb").write(t2.encode("utf-8"))
    print("Runner.rc", "changed" if t2 != txt else "unchanged")

# 3) 아이콘
ico = os.path.join(root, "windows_patch", "app_icon.ico")
dst = os.path.join(runner, "resources", "app_icon.ico")
if os.path.exists(ico) and os.path.isdir(os.path.dirname(dst)):
    shutil.copy(ico, dst)
    print("icon copied")
print("patched", app)
