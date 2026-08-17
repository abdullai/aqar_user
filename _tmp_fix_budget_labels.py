# -*- coding: utf-8 -*-
from pathlib import Path

p = Path(r"d:/aqar_user/lib/screens/create_market_property_request_page.dart")
t = p.read_text(encoding="utf-8")
t2 = t
t2 = t2.replace("ميزانية من", "المبلغ من")
t2 = t2.replace("ميزانية إلى", "المبلغ إلى")
t2 = t2.replace("'Budget min'", "'Amount min'")
t2 = t2.replace("'Budget max'", "'Amount max'")
t2 = t2.replace(
    "const cur = AppMoney.saudiRiyalSignUnicode;",
    "final cur = AppMoney.sarUiSuffix(isAr: _isAr);",
)
print("ميزانية left:", t2.count("ميزانية"))
print("Budget min left:", t2.count("Budget min"))
p.write_text(t2, encoding="utf-8")
print("ok")
