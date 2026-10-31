module Format exposing (date, size)

import Time


{-| "48 KB", "1.2 MB". Below 1 MB sizes round up, as File Explorer does.
-}
size : Int -> String
size bytes =
    if bytes < 1024 then
        String.fromInt bytes ++ " B"

    else if bytes < 1024 ^ 2 then
        String.fromInt ((bytes + 1023) // 1024) ++ " KB"

    else if bytes < 1024 ^ 3 then
        oneDecimal (toFloat bytes / (1024 ^ 2)) ++ " MB"

    else if bytes < 1024 ^ 4 then
        oneDecimal (toFloat bytes / (1024 ^ 3)) ++ " GB"

    else
        oneDecimal (toFloat bytes / (1024 ^ 4)) ++ " TB"


oneDecimal : Float -> String
oneDecimal value =
    let
        tenths =
            round (value * 10)
    in
    String.fromInt (tenths // 10) ++ "." ++ String.fromInt (modBy 10 tenths)


{-| Formats a time with a pattern using yyyy, MM, dd, HH, mm and ss.
-}
date : String -> Time.Zone -> Int -> String
date pattern zone millis =
    let
        t =
            Time.millisToPosix millis

        pad2 n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    pattern
        |> String.replace "yyyy" (String.fromInt (Time.toYear zone t))
        |> String.replace "MM" (pad2 (monthNumber (Time.toMonth zone t)))
        |> String.replace "dd" (pad2 (Time.toDay zone t))
        |> String.replace "HH" (pad2 (Time.toHour zone t))
        |> String.replace "mm" (pad2 (Time.toMinute zone t))
        |> String.replace "ss" (pad2 (Time.toSecond zone t))


monthNumber : Time.Month -> Int
monthNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
