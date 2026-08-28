//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import Quickshell
import qs.modules.bar

ShellRoot {
    // One bar per display, recreated automatically on hotplug.
    Variants {
        model: Quickshell.screens

        Bar {}
    }
}
