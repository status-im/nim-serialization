# nim-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}

import ../serialization/case_objects

type
  HelperSelector* = enum
    helperX = 1
    helperY = 2

  HelperCaseObject* {.allowDiscriminatorsWithoutZero.} = object
    case selector*: HelperSelector
    of helperX:
      xData*: int
    of helperY:
      yData*: string

  HiddenCaseObject {.allowDiscriminatorsWithoutZero.} = object
    case selector: HelperSelector
    of helperX:
      xData: int
    of helperY:
      yData: string

func hiddenCaseObject*(yData: string): HiddenCaseObject =
  HiddenCaseObject.init(selector = helperY, yData = yData)
