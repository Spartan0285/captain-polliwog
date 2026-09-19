/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

/*
 * AutoFill's side of the page. Captain Polliwog calls this with a command:
 *   "survey"   which kinds of fields the page has
 *   "fill"     fills fields from values keyed by kind
 *   "capture"  a login typed into the page, before it goes away
 * and gets text back, fields separated by U+0001 (Tiger has no JSON
 * parser for the app's side). Fields are known by their autocomplete attribute,
 * else by name, id, placeholder and label. A card's security code is never
 * filled. ES5, for any engine.
 */
(function (command, values) {
    "use strict";

    var PATTERNS = [
        ["cc-csc", /cvv|cvc|csc|security.?code|card.?verif/],
        ["cc-number", /card.?num|cc.?num|cardnumber|ccnum|credit.?card|card.?no/],
        ["cc-name", /name.?on.?card|card.?holder|cc.?name|cardholder/],
        ["cc-exp-month", /exp.*mo|cc.?month|card.?month|expmonth/],
        ["cc-exp-year", /exp.*y(ea)?r|cc.?year|card.?year|expyear/],
        ["cc-exp", /expir|exp.?date|mm.?\/?.?yy/],
        ["email", /e.?mail/],
        ["given-name", /first.?name|given.?name|fname|forename/],
        ["family-name", /last.?name|surname|family.?name|lname/],
        ["tel", /phone|tel\b|mobile|telephone/],
        ["address-line2", /address.?(line)?.?2|apt|suite|unit\b|addr2/],
        ["address-line1", /address.?(line)?.?1|street|addr1|address/],
        ["address-level2", /city|town|locality/],
        ["address-level1", /state|province|region|county/],
        ["postal-code", /zip|postal|postcode/],
        ["country", /country/],
        ["name", /full.?name|^name$|your.?name|\bname\b/],
        ["username", /user|login|account|identifier|signin/]
    ];

    function visible(element) {
        return !element.disabled && !element.readOnly && (element.offsetWidth > 0 || element.offsetHeight > 0);
    }

    function labelText(element) {
        var text = element.getAttribute("aria-label") || "";
        if (element.id) {
            var labels = document.getElementsByTagName("label");
            for (var i = 0; i < labels.length; i++) {
                if (labels[i].htmlFor === element.id)
                    text += " " + labels[i].textContent;
            }
        }
        if (element.parentNode && element.parentNode.tagName === "LABEL")
            text += " " + element.parentNode.textContent;
        return text;
    }

    function kindOf(element) {
        var tag = element.tagName, type = (element.type || "").toLowerCase();
        if (tag === "INPUT" && /^(hidden|submit|button|image|reset|checkbox|radio|file|search)$/.test(type))
            return null;
        var tokens = (element.getAttribute("autocomplete") || "").toLowerCase().split(/\s+/);
        var auto = tokens[tokens.length - 1];
        if (auto === "current-password" || auto === "new-password" || type === "password")
            return "password";
        if (auto && auto !== "on" && auto !== "off")
            return auto;
        if (type === "email")
            return "email";
        if (type === "tel")
            return "tel";
        var text = ((element.name || "") + " " + (element.id || "") + " " + (element.getAttribute("placeholder") || "") + " " + labelText(element)).toLowerCase();
        for (var i = 0; i < PATTERNS.length; i++) {
            if (PATTERNS[i][1].test(text))
                return PATTERNS[i][0];
        }
        return null;
    }

    function fields() {
        var list = [], elements = document.querySelectorAll("input, select, textarea");
        for (var i = 0; i < elements.length; i++) {
            if (visible(elements[i]))
                list.push({ element: elements[i], kind: kindOf(elements[i]) });
        }
        return list;
    }

    // The field a login's username goes in: a username or email field, else
    // the last text field before the password.
    function usernameField(list) {
        var passwordIndex = -1, i;
        for (i = 0; i < list.length; i++) {
            if (list[i].kind === "password") {
                passwordIndex = i;
                break;
            }
        }
        for (i = 0; i < list.length; i++) {
            if (list[i].kind === "username" && (passwordIndex < 0 || i < passwordIndex))
                return list[i];
        }
        for (i = (passwordIndex < 0 ? list.length : passwordIndex) - 1; i >= 0; i--) {
            var type = (list[i].element.type || "").toLowerCase();
            if (list[i].element.tagName === "INPUT" && (type === "text" || type === "email" || type === "") && (list[i].kind === "email" || list[i].kind === null || list[i].kind === "username"))
                return list[i];
        }
        return null;
    }

    // Sets a value the way typing would, so pages built with React and the
    // like notice.
    function setValue(element, value) {
        if (element.tagName === "SELECT") {
            var wanted = String(value).toLowerCase();
            for (var i = 0; i < element.options.length; i++) {
                var option = element.options[i];
                if (option.value.toLowerCase() === wanted || option.text.toLowerCase() === wanted
                    || (wanted.length > 2 && option.text.toLowerCase().indexOf(wanted) === 0)) {
                    element.selectedIndex = i;
                    break;
                }
            }
        } else {
            var descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), "value");
            if (descriptor && descriptor.set)
                descriptor.set.call(element, value);
            else
                element.value = value;
        }
        ["input", "change"].forEach(function (name) {
            var event = document.createEvent("HTMLEvents");
            event.initEvent(name, true, false);
            element.dispatchEvent(event);
        });
    }

    var list = fields(), i;

    if (command === "survey") {
        var kinds = {}, user = usernameField(list);
        for (i = 0; i < list.length; i++) {
            if (list[i].kind)
                kinds[list[i].kind] = true;
        }
        return [Object.keys(kinds).join(","), user ? user.element.value : "", user ? "1" : "0"].join("\u0001");
    }

    if (command === "fill") {
        var filled = 0, userField = usernameField(list);
        if (values.username !== undefined && userField) {
            setValue(userField.element, values.username);
            filled++;
        }
        for (i = 0; i < list.length; i++) {
            var kind = list[i].kind;
            if (!kind || kind === "cc-csc" || (values.username !== undefined && userField && list[i] === userField))
                continue;
            if (kind === "cc-exp" && values["cc-exp-month"] && values["cc-exp-year"])
                values["cc-exp"] = values["cc-exp-month"] + "/" + String(values["cc-exp-year"]).slice(-2);
            if (kind === "name" && values.name === undefined && values["given-name"])
                values.name = values["given-name"] + " " + (values["family-name"] || "");
            if (values[kind] !== undefined && values[kind] !== "" && (!list[i].element.value || kind === "password")) {
                setValue(list[i].element, values[kind]);
                filled++;
            }
        }
        return String(filled);
    }

    if (command === "capture") {
        var password = null, captured = usernameField(list);
        for (i = 0; i < list.length; i++) {
            if (list[i].kind === "password" && list[i].element.value) {
                password = list[i].element.value;
                break;
            }
        }
        var typed = window.__polliwogTypedLogin;
        if (!password && typed && typed.password) {
            // Typed here, then cleared or replaced before the page moved on.
            password = typed.password;
            if (!captured || !captured.element.value)
                captured = typed.username ? { element: { value: typed.username } } : captured;
        }
        if (typed)
            window.__polliwogTypedLogin = null;
        var username = captured ? captured.element.value : "";
        if (!username) {
            // Sign-ins done in steps keep the username in a hidden field.
            var all = document.querySelectorAll("input");
            for (i = 0; i < all.length && !username; i++) {
                var auto = (all[i].getAttribute("autocomplete") || "").toLowerCase();
                if (all[i].value && (all[i].type === "email" || /username|email/.test(auto) || /identifier|username|email|login/.test((all[i].name || "").toLowerCase())))
                    username = all[i].value;
            }
        }
        return [password || "", username].join("\u0001");
    }
    return "";
})
