class _DummyProgress:
    def progress(self, *args, **kwargs):
        return None

class _DummyEmpty:
    def text(self, *args, **kwargs):
        return None

class _DummySessionState(dict):
    pass

def write(*args, **kwargs):
    print(*args)

def info(*args, **kwargs):
    print(*args)

def warning(*args, **kwargs):
    print(*args)

def error(*args, **kwargs):
    print(*args)

def progress(*args, **kwargs):
    return _DummyProgress()

def empty(*args, **kwargs):
    return _DummyEmpty()

session_state = _DummySessionState()
