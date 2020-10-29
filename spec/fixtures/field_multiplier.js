// fieldName
// multiplier

function filter(event) {
  var value = Number( event.getField(fieldName) ) * multiplier
  event.setField(fieldName, value)
  if (env === 'debug') print("calculated value: " + value + " for " + event);
  // Filter blocks must return any events that are to be passed on
  // return a nil or [] here if all events are to be cancelled
  // You can even return one or more brand new events here!
  return [ event ]
}

/*
test "standard flow" do
  parameters do
    { "field" => "myfield", "multiplier" => 3 }
  end

  in_event { { "myfield" => 123 } }

  expect("there to be only one result event") do |events|
    events.size == 1
  end

  expect("result to be equal to 123*3(369)") do |events|
    events.first.get("myfield") == 369
  end
end
*/