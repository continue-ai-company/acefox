import asyncio
import json

import pytest
from webdriver.bidi.modules.input import Actions, get_element_origin
from webdriver.bidi.modules.script import ContextTarget

pytestmark = pytest.mark.asyncio


async def set_companion_window_state(
    bidi_session, context, *, level="normal", visibility="unchanged"
):
    result = await bidi_session.send_command(
        "browsingContext.setCompanionWindowState",
        {
            "context": context,
            "level": level,
            "visibility": visibility,
        },
    )
    return await result


async def get_page_state(bidi_session, context):
    result = await bidi_session.script.evaluate(
        expression="""JSON.stringify({
            bounds: {
                x: window.screenX,
                y: window.screenY,
                width: window.outerWidth,
                height: window.outerHeight,
            },
            visibility: document.visibilityState,
            timerTicks: window.timerTicks,
            inputValue: document.querySelector("input").value,
            clickCount: window.clickCount,
            wheelCount: window.wheelCount,
            scrollTop: document.querySelector("#scrollable").scrollTop,
        })""",
        target=ContextTarget(context),
        await_promise=False,
    )
    return json.loads(result["value"])


async def test_transparent_keeps_context_active_and_accepts_bidi_input(
    bidi_session, top_context, inline, get_element
):
    context = top_context["context"]
    page = inline(
        """
        <input autofocus>
        <button id="button">click</button>
        <div id="scrollable" style="height: 100px; overflow: auto">
          <div style="height: 1000px">scrollable</div>
        </div>
        <script>
          window.timerTicks = 0;
          window.clickCount = 0;
          window.wheelCount = 0;
          setInterval(() => window.timerTicks++, 10);
          document.querySelector("button").addEventListener(
            "click",
            () => window.clickCount++
          );
          document.querySelector("#scrollable").addEventListener(
            "wheel",
            () => window.wheelCount++
          );
          document.querySelector("input").focus();
        </script>
        """,
        protocol="http",
    )
    await bidi_session.browsing_context.navigate(
        context=context, url=page, wait="complete"
    )

    initial_state = await get_page_state(bidi_session, context)

    try:
        result = await set_companion_window_state(
            bidi_session, context, visibility="transparent"
        )
        assert result["level"] == "normal"
        assert result["visibility"] == "transparent"
        assert isinstance(result["active"], bool)

        await asyncio.sleep(0.2)
        transparent_state = await get_page_state(bidi_session, context)
        assert transparent_state["visibility"] == "visible"
        assert transparent_state["timerTicks"] > initial_state["timerTicks"]
        assert transparent_state["bounds"] == initial_state["bounds"]

        key_actions = Actions()
        key_actions.add_key().send_keys("acefox")
        await bidi_session.input.perform_actions(actions=key_actions, context=context)

        button = await get_element("#button")
        pointer_actions = Actions()
        (
            pointer_actions.add_pointer()
            .pointer_move(0, 0, origin=get_element_origin(button))
            .pointer_down(button=0)
            .pointer_up(button=0)
        )
        await bidi_session.input.perform_actions(
            actions=pointer_actions, context=context
        )

        scrollable = await get_element("#scrollable")
        wheel_actions = Actions()
        wheel_actions.add_wheel().scroll(
            x=0,
            y=0,
            delta_x=0,
            delta_y=100,
            origin=get_element_origin(scrollable),
        )
        await bidi_session.input.perform_actions(actions=wheel_actions, context=context)
        await asyncio.sleep(0.1)

        input_state = await get_page_state(bidi_session, context)
        assert input_state["inputValue"] == "acefox"
        assert input_state["clickCount"] == 1
        assert input_state["wheelCount"] == 1
        assert input_state["scrollTop"] > 0
        assert input_state["bounds"] == initial_state["bounds"]

        for index in range(20):
            visibility = "transparent" if index % 2 == 0 else "shown"
            result = await set_companion_window_state(
                bidi_session, context, visibility=visibility
            )
            assert result["visibility"] == visibility

        result = await set_companion_window_state(
            bidi_session, context, visibility="hidden"
        )
        assert result["visibility"] == "hidden"

        result = await set_companion_window_state(
            bidi_session, context, visibility="shown"
        )
        assert result["visibility"] == "shown"
        shown_state = await get_page_state(bidi_session, context)
        assert shown_state["bounds"] == initial_state["bounds"]

        pointer_actions = Actions()
        (
            pointer_actions.add_pointer()
            .pointer_move(0, 0, origin=get_element_origin(button))
            .pointer_down(button=0)
            .pointer_up(button=0)
        )
        await bidi_session.input.perform_actions(
            actions=pointer_actions, context=context
        )
        shown_state = await get_page_state(bidi_session, context)
        assert shown_state["clickCount"] == 2
    finally:
        await set_companion_window_state(bidi_session, context, visibility="shown")
