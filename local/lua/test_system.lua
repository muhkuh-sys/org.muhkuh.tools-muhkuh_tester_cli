local class = require 'pl.class'
local TestSystem = class()


function TestSystem:_init()
  self.strTesterVersion = '${PROJECT_VERSION}'
  self.strTesterVcsVersion = '${PROJECT_VERSION_VCS}'

  -- Get the LUA version number in the form major * 100 + minor .
  local strMaj, strMin = string.match(_VERSION, '^Lua (%d+)%.(%d+)$')
  if strMaj~=nil then
    self.LUA_VER_NUM = tonumber(strMaj) * 100 + tonumber(strMin)
  end

  -- The "show parameter" mode is disabled by default.
  self.fShowParameters = false

  -- Run over all available test cases and get the test modules.
  self.atModules = {}

  -- This list collects all parameters from the CLI. They are not split into their components.
  self.astrRawParameters = {}

  -- This list collects all test cases to run.
  self.auiTests = nil

  -- This is the list of the system parameters.
  self.m_atSystemParameter = nil

  self.pl = require'pl.import_into'()
  self.argparse = require 'argparse'
  self.mhash = require 'mhash'
  self.TestDescription = require 'test_description'
  self.zmq = require 'lzmq'
  self.json = require 'dkjson'
  self.date = require 'date'

  -- This is a log writer connected to all outputs (console and optionally file).
  -- It is used to create new log targets with special prefixes for each test.
  self.tLogWriter = nil
  -- This is the selected log level.
  self.strLogLevel = nil

  -- This is a logger with "SYSTEM" prefix.
  self.tLogSystem = nil

  self.m_zmqPort = nil
  self.m_zmqContext = nil
  self.m_zmqSocket = nil
  self.m_atTestExecutionParameter = nil
end



function TestSystem:__connect()
  local usServerPort = self.m_zmqPort
  if usServerPort==0 then
    print('Not connecting to a server as the server port is 0.')
  else
    local strAddress = string.format('tcp://127.0.0.1:%d', usServerPort)
    print(string.format("Connecting to %s", strAddress))

    -- Create the 0MQ context.
    local zmq = self.zmq
    local tZContext, strErrorCtx = zmq.context()
    if tZContext==nil then
      error('Failed to create ZMQ context: ' .. tostring(strErrorCtx))
    end
    self.m_zmqContext = tZContext

    -- Create the socket.
    local tZSocket, strErrorSocket = tZContext:socket(zmq.PAIR)
    if tZSocket==nil then
      error('Failed to create ZMQ socket: ' .. tostring(strErrorSocket))
    end

    -- Connect the socket to the server.
    local tResult, strErrorConnect = tZSocket:connect(strAddress)
    if tResult==nil then
      error('Failed to connect the socket: ' .. tostring(strErrorConnect))
    end
    self.m_zmqSocket = tZSocket

    print(string.format('0MQ socket connected to tcp://127.0.0.1:%d', usServerPort))
  end
end



function TestSystem:__disconnect()
  local m_zmqSocket = self.m_zmqSocket
  if m_zmqSocket~=nil then
    if m_zmqSocket:closed()==false then
      m_zmqSocket:close()
    end
    self.m_zmqSocket = nil
  end

  local m_zmqContext = self.m_zmqContext
  if m_zmqContext~=nil then
    m_zmqContext:destroy()
    self.m_zmqContext = nil
  end
end



function TestSystem:__sendTestRunStart()
  local tZmqSocket = self.m_zmqSocket
  if tZmqSocket~=nil then
    local tData = {
      attributes = self.m_atSystemParameter
    }
    local strJson = self.json.encode(tData)
    tZmqSocket:send('TDS'..strJson)
  end
end



function TestSystem:__sendTestRunFinished()
  local tZmqSocket = self.m_zmqSocket
  if tZmqSocket~=nil then
    tZmqSocket:send('TDF')
  end
end



function TestSystem:__sendTestStepStart(uiStepIndex, strTestCaseId, strTestCaseName)
  local tZmqSocket = self.m_zmqSocket
  if tZmqSocket~=nil then
    local tData = {
      stepIndex=uiStepIndex,
      testId=strTestCaseId,
      testName=strTestCaseName,
      attributes = self.m_atSystemParameter
    }
    local strJson = self.json.encode(tData)
    tZmqSocket:send('TSS'..strJson)
  end
end



function TestSystem:__sendTestStepFinished(strTestStepState)
  local tZmqSocket = self.m_zmqSocket
  if tZmqSocket~=nil then
    local tData = {
      testStepState=strTestStepState
    }
    local strJson = self.json.encode(tData)
    tZmqSocket:send('TSF'..strJson)
  end
end



function TestSystem:collect_testcases()
  local tLogSystem = self.tLogSystem
  local tTestDescription = self.tTestDescription
  local tResult = true

  for _, uiTestCase in ipairs(self.auiTests) do
    -- Does a test with this number already exist?
    if self.atModules[uiTestCase]~=nil then
      tLogSystem.fatal('More than one test with the index %d exists.', uiTestCase)
      tResult = nil
      break
    end

    -- Create the filename for the test case.
    local strTestCaseFilename = string.format("test%02d", uiTestCase)

    -- Load the test case.
    local tClass = require(strTestCaseFilename)
    local tModule = tClass(uiTestCase, self.tLogWriter, self.strLogLevel)

    -- The ID defined in the class must match the ID from the test description.
    local strDefinitionId = tTestDescription:getTestCaseName(uiTestCase)
    local strModuleId = tModule.CFG_strTestName
    if strModuleId~=strDefinitionId then
      tLogSystem.fatal('The ID of test %d differs between the test definition and the module.', uiTestCase)
      tLogSystem.debug('The ID of test %d in the test definition is "%s".', uiTestCase, strDefinitionId)
      tLogSystem.debug('The ID of test %d in the module is "%s".', uiTestCase, strModuleId)
      tResult = nil
      break
    end

    self.atModules[uiTestCase] = tModule
  end

  return tResult
end


function TestSystem.print_aligned(aLines, strFormat)
  -- Get the maximum size of the lines.
  local sizLineMax = 0
  for _, aLine in ipairs(aLines) do
    local sizLine = string.len(aLine[1])
    sizLineMax = math.max(sizLineMax, sizLine)
  end

  -- Print all strings with the appropriate fillup.
  for _, aLine in ipairs(aLines) do
    local sizFillup = sizLineMax - string.len(aLine[1])
    local astrTexts = aLine[2]
    print(string.format(strFormat, aLine[1] .. string.rep(" ", sizFillup), astrTexts[1]))
    for iLineCnt=2,#astrTexts,1 do
      print(string.format(strFormat, string.rep(" ", sizLineMax), astrTexts[iLineCnt]))
    end
  end
end



function TestSystem:show_all_parameters()
  print("All parameters:")
  print("")
  for _, uiTestCase in ipairs(self.auiTests) do
    local tModule = self.atModules[uiTestCase]
    if tModule==nil then
      self.tLogSystem.fatal('Test case %02d does not exist.', uiTestCase)
    else
      local strTestName = tModule.CFG_strTestName
      print(string.format("  Test case %02d: '%s'", uiTestCase, strTestName))

      local atPrint = {}
      for _, tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
        -- Is this parameter an input or an output?
        local strInOut = 'IN '
        if tParameter.fIsOutput==true then
          strInOut = 'OUT'
        end

        local strDefault = "no default value"
        if tParameter.fHasDefaultValue==true then
          strDefault = string.format("default: %s", tostring(tParameter.tDefaultValue))
        end

        table.insert(atPrint, {
          string.format("%s %02d:%s", strInOut, uiTestCase, tParameter.strName),
          {tParameter.strHelp, strDefault}
        })
      end
      self.print_aligned(atPrint, "    %s  %s")
      print("")
    end
  end
end



--- Get the index of a module.
-- Search a module by its name and return the index.
-- @param strModuleName The module name to search.
-- @return The index if the name was found or nil if the name was not found.
function TestSystem:get_module_index(strModuleName)
  return self.tTestDescription:getTestCaseIndex(strModuleName)
end



function TestSystem:parse_commandline_arguments()
  local mime = require 'mime.core'

  local atLogLevels = {
    'debug',
    'info',
    'warning',
    'error',
    'fatal'
  }

  local tParser = self.argparse('tester', 'A test framework.')
  -- "--version" is special. It behaves like a command and is processed immediately during parsing.
  tParser:flag('--version')
    :description('Show the version and exit.')
    :action(function()
      print(string.format('tester V%s %s', self.strTesterVersion, self.strTesterVcsVersion))
      os.exit(0, true)
    end)
  tParser:argument('testcase', 'Run only testcase INDEX.')
    :argname('<INDEX>')
    :convert(function (strArg)
      local ulArg = tonumber(strArg)
      if ulArg==nil then
        return nil, string.format('The test index "%s" is not a number.', strArg)
      else
        return ulArg
      end
    end)
    :args('*')
    :target('auiTests')
  tParser:flag('-s --show-parameters')
    :description('Show all available parameters for all test cases. Do not run any tests.')
    :default(false)
    :target('fShowParameters')
  tParser:mutex(
    tParser:flag('--color')
      :description('Use colors to beautify the console output. This is the default on Linux.')
      :action("store_true")
      :target('fUseColor'),
    tParser:flag('--no-color')
      :description('Do not use colors for the console output. This is the default on Windows.')
      :action("store_false")
      :target('fUseColor')
  )
  tParser:option('-l --logfile')
    :description('Write all output to FILE.')
    :argname('<FILE>')
    :default(nil)
    :target('strLogFileName')
  tParser:mutex(
    tParser:flag('-i --interactive-plugin-selection')
      :description('Ask the user to pick a plugin. The default is to select a plugin automatically.')
      :default(false)
      :target('fInteractivePluginSelection'),
    tParser:option('-S --server-port')
      :description(
        'Connect to a server on localhost with port number PORT. The default of 0 deactivates the connection.'
      )
      :argname('PORT')
      :default(0)
      :convert(tonumber)
      :target('usServerPort')
  )
  tParser:option('-p --parameter')
    :description('Set the parameter PARAMETER of test case TEST-CASE-ID to the value VALUE.')
    :argname('<TEST-CASE-ID>:<PARAMETER>=<VALUE>')
    :count('*')
    :convert(function(strArg)
      local tMatch = string.match(strArg, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
      if tMatch==nil then
        return nil, string.format("The parameter definition has an invalid format: '%s'", strArg)
      else
        return strArg
      end
    end)
    :target('astrRawParameters')
  tParser:option('-b --base64-parameter')
    :description('Set the parameter PARAMETER of test case TEST-CASE-ID to the base64 decoded value of BASE64VALUE.')
    :argname('<TEST-CASE-ID>:<PARAMETER>=<BASE64VALUE>')
    :count('*')
    :convert(function(strArg)
      local tMatch0, tMatch1, tMatch2 = string.match(strArg, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
      if tMatch0==nil then
        return nil, string.format("The parameter definition has an invalid format: '%s'", strArg)
      else
        local strDecoded = mime.unb64(tMatch2)
        if strDecoded==nil then
          return nil, string.format("The value of the parameter definition is no valid base64: '%s'", strArg)
        else
          return tMatch0 .. ':' .. tMatch1 .. '=' .. strDecoded
        end
      end
    end)
    :target('astrRawParameters')
  tParser:option('-P --parameter-file')
    :description('Read parameters from FILE.')
    :argname('<FILE>')
    :count('*')
    :convert(function(strArg)
      return '@' .. strArg
    end)
    :target('astrRawParameters')
  tParser:option('-v --verbose')
    :description(
      string.format(
        'Set the verbosity level to LEVEL. Possible values for LEVEL are %s.',
        table.concat(atLogLevels, ', ')
      )
    )
    :argname('<LEVEL>')
    :default('warning')
    :convert(function(strArg)
      local tIdx = self.pl.tablex.find(atLogLevels, strArg)
      if tIdx==nil then
        return nil, string.format(
          'Invalid verbosity level "%s". Possible values are %s.',
          strArg,
          table.concat(atLogLevels, ', ')
        )
      else
        return strArg
      end
    end)
    :target('strLogLevel')
  tParser:option('--verbose-console')
    :description(
      string.format(
        'Set the verbosity level for the console output to LEVEL. Possible values for LEVEL are %s.',
        table.concat(atLogLevels, ', ')
      )
    )
    :argname('<LEVEL>')
    :convert(function(strArg)
      local tIdx = self.pl.tablex.find(atLogLevels, strArg)
      if tIdx==nil then
        return nil, string.format(
          'Invalid console verbosity level "%s". Possible values are %s.',
          strArg,
          table.concat(atLogLevels, ', ')
        )
      else
        return strArg
      end
    end)
    :target('strLogLevelConsole')
  tParser:option('--verbose-file')
    :description(
      string.format(
        'Set the verbosity level for the file output to LEVEL. Possible values for LEVEL are %s.',
        table.concat(atLogLevels, ', ')
      )
    )
    :argname('<LEVEL>')
    :convert(function(strArg)
      local tIdx = self.pl.tablex.find(atLogLevels, strArg)
      if tIdx==nil then
        return nil, string.format(
          'Invalid file verbosity level "%s". Possible values are %s.',
          strArg,
          table.concat(atLogLevels, ', ')
        )
      else
        return strArg
      end
    end)
    :target('strLogLevelFile')
  tParser:option('-d --debug')
    :description('Set the IP address and the port number for the remote debugging.')
    :argname('<IP>:<Port NUMBER>')
    :convert(
      function(strArg)
        local tIp0, tIp1, tIp2, tIp3, tPortNumb = string.match(strArg, '^(%d+)%.(%d+)%.(%d+)%.(%d+)%:(%d+)$')
        if tIp0==nil then
          return nil, string.format(
            "The given IP and port number '%s' (<IP>:<Port NUMBER>) has an invalid format. " ..
            "It should be [0-255].[0-255].[0-255].[0-255]:[0-65535].",
            strArg
          )
        else
          local ucIp0 = tonumber(tIp0)
          local ucIp1 = tonumber(tIp1)
          local ucIp2 = tonumber(tIp2)
          local ucIp3 = tonumber(tIp3)
          local uiPortNumb = tonumber(tPortNumb)

          if ucIp0<0 or ucIp0>255 or ucIp1<0 or ucIp1>255 or ucIp2<0 or ucIp2>255 or ucIp3<0 or ucIp3>255 then
            return nil, string.format('The componentes of the IP must be 0<=d<=255 .')
          elseif uiPortNumb <0 or uiPortNumb > 65535 then
            return nil, string.format('The port number must be 0<=d<=65535 .')
          else
            local tArg ={
              IP = ucIp0 .. '.' .. ucIp1 .. '.' .. ucIp2 .. '.' .. ucIp3,
              Port = uiPortNumb
              }
            return tArg
          end
        end
      end
    )
    :target('tDebugParam')

  local tArgs = tParser:parse()

  -- debug parameters <IP>:<port number>
  self.tDebugParam = tArgs.tDebugParam

  -- Save the selected log level.
  self.strLogLevel = tArgs.strLogLevel
  -- Get the log levels for the console and file. Fallback to the log level if they are not set.
  local strLogLevelConsole = tArgs.strLogLevelConsole or tArgs.strLogLevel
  local strLogLevelFile = tArgs.strLogLevelFile or tArgs.strLogLevel

  self.fShowParameters = tArgs.fShowParameters

  self.m_zmqPort = tArgs.usServerPort
  self:__connect()

  local fUseColor = tArgs.fUseColor
  if fUseColor==nil then
    if self.pl.path.is_windows==true then
      -- Running on windows. Do not use colors by default as cmd.exe
      -- does not support ANSI on all windows versions.
      fUseColor = false
    else
      -- Running on Linux. Use colors by default.
      fUseColor = true
    end
  end

  local tZmqSocket = self.m_zmqSocket

  -- Collect all log writers.
  local atLogWriters = {}

  -- Create the console logger if no server connection exists.
  if tZmqSocket==nil then
    local tLogWriterConsole
    if fUseColor==true then
      tLogWriterConsole = require 'log.writer.console.color'.new()
    else
      tLogWriterConsole = require 'log.writer.console'.new()
    end
    table.insert(atLogWriters, require "log.writer.filter".new(strLogLevelConsole, tLogWriterConsole))
  end

  -- Create the file logger if requested.
  if tArgs.strLogFileName~=nil then
    local tLogWriterFile = require "log.writer.filter".new(
      strLogLevelFile,
      require 'log.writer.file'.new{
        log_name = tArgs.strLogFileName
      }
    )
    table.insert(atLogWriters, tLogWriterFile)
  end

  -- Create the 0MQ logger if a socket exists.
  if tZmqSocket~=nil then
    -- Now create the logger. It sends the data to the ZMQ socket.
    -- It does not use the formatter function 'fnFormat' or the date 'tDate'.
    -- This is done on the receiver side.
    local tLogWriterZmq = function(_, strMessage, uiLevel, _)
      tZmqSocket:send(string.format('LOG%d,%s', uiLevel, strMessage))
    end
    table.insert(atLogWriters, tLogWriterZmq)
  end

  -- Combine all writers.
  if self.LUA_VER_NUM==501 then
    self.tLogWriter = require 'log.writer.list'.new(unpack(atLogWriters))
  else
    self.tLogWriter = require 'log.writer.list'.new(table.unpack(atLogWriters))
  end

  -- Create a new log target with "SYSTEM" prefix.
  local tLogWriterSystem = require 'log.writer.prefix'.new('[System] ', self.tLogWriter)
  self.tLogSystem = require "log".new(
    -- maximum log level
    self.strLogLevel,
    tLogWriterSystem,
    -- Formatter
    require "log.formatter.format".new()
  )


  self.astrRawParameters = tArgs.astrRawParameters

  -- If no test cases were specified run all of them.
  if #tArgs.auiTests~=0 then
    self.auiTests = tArgs.auiTests
  end
end



function TestSystem:process_one_parameter(strParameterLine, atCliParameters)
  local tLogSystem = self.tLogSystem
  local tResult = true

  -- Process all lines which are not..
  --  the "end of file" marker,
  --  empty,
  --  starting with a '#' (this is used in parameter files).
  if strParameterLine~=nil and
     string.len(strParameterLine)~=0 and
     string.sub(strParameterLine, 1, 1)~="#" then

    -- This is a parameter file if the entry starts with "@".
    if string.sub(strParameterLine, 1, 1)=="@" then
      -- Get the filename without the '@'.
      local strFilename = string.sub(strParameterLine, 2)
      tLogSystem.debug('Processing parameter file "%s".', strFilename)
      if self.pl.path.exists(strFilename)==nil then
        tLogSystem.fatal('The parameter file "%s" does not exist.', strFilename)
        tResult = nil
      else
        -- Iterate over all lines.
        for strLine in io.lines(strFilename) do
          if strLine~=nil then
            tResult = self:process_one_parameter(strLine, atCliParameters)
            if tResult~=true then
              break
            end
          end
        end
      end
    else
      tLogSystem.debug('Processing parameter "%s".', strParameterLine)
      local uiTestCase
      -- Try to parse the parameter line with a test number ("01:key=value").
      local strTestCase, strParameterName, strValue = string.match(strParameterLine, "([0-9]+):([0-9a-zA-Z_]+)=(.*)")
      if strTestCase==nil then
        -- Try to parse the parameter line with a test name ("EthernetTest:key=value").
        strTestCase, strParameterName, strValue = string.match(strParameterLine, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
        if strTestCase==nil then
          tLogSystem.fatal("The parameter definition has an invalid format: '%s'", strParameterLine)
          tResult = nil
        else
          if strTestCase=='system' then
            uiTestCase = 0
          else
            -- Get the number for the test case name.
            uiTestCase = self:get_module_index(strTestCase)
            if uiTestCase==nil then
              tLogSystem.fatal(
                'The parameter "%s" uses an unknown test name: "%s".',
                strParameterLine,
                strTestCase
              )
              tResult = nil
            end
          end
        end
      else
        uiTestCase = tonumber(strTestCase)
        if uiTestCase==nil then
          tLogSystem.fatal(
            'The parameter "%s" uses an invalid number for the test index: "%s".',
            strParameterLine,
            strTestCase
          )
          tResult = nil
        end
      end

      if tResult~=nil then
        table.insert(atCliParameters, {id=uiTestCase, name=strParameterName, value=strValue})
      end
    end
  end

  return tResult
end



function TestSystem:collect_parameters()
  local tLogSystem = self.tLogSystem
  local tTestDescription = self.tTestDescription
  local tResult = true

  -- Collect all parameters from the command line.
  local atCliParameters = {}
  for _, strParameter in ipairs(self.astrRawParameters) do
    tResult = self:process_one_parameter(strParameter, atCliParameters)
    if tResult~=true then
      break
    end
  end

  -- Apply all system parameters.
  for _, tParam in pairs(atCliParameters) do
    -- Is this a system parameter?
    if tParam.id==0 then
      -- Set the parameter.
      tLogSystem.debug('Setting system parameter "%s" to %s.', tParam.name, tParam.value)
      self.m_atSystemParameter[tParam.name] = tParam.value
    end
  end

  if tResult==true then
    -- Get all test names.
    local astrTestNames = tTestDescription:getTestNames()

    -- Loop over all active tests and apply the tests from the XML.
    local uiNumberOfTests = tTestDescription:getNumberOfTests()
    for uiTestIndex = 1, uiNumberOfTests do
      local tModule = self.atModules[uiTestIndex]
      local strTestCaseName = astrTestNames[uiTestIndex]

      if tModule==nil then
        tLogSystem.debug('Skipping deactivated test %02d:%s .', uiTestIndex, strTestCaseName)
      else
        -- Get the parameters for the module.
        local atParametersModule = tModule.atParameter or {}

        -- Get the parameters from the XML.
        local atParametersXml = tTestDescription:getTestCaseParameters(uiTestIndex)
        for _, tParameter in ipairs(atParametersXml) do
          local strParameterName = tParameter.name
          local strParameterValue = tParameter.value
          local strParameterConnection = tParameter.connection

          -- Does the parameter exist?
          tParameter = atParametersModule[strParameterName]
          if tParameter==nil then
            tLogSystem.fatal(
              'The parameter "%s" does not exist in test case %d (%s).',
              strParameterName,
              uiTestIndex,
              strTestCaseName
            )
            tResult = nil
            break
          -- Is the parameter an "output"?
          elseif tParameter.fIsOutput==true then
            tLogSystem.fatal(
              'The parameter "%s" in test case %d (%s) is an output.',
              strParameterName,
              uiTestIndex,
              strTestCaseName
            )
            tResult = nil
            break
          else
            if strParameterValue~=nil then
              -- This is a direct assignment of a value.
              tParameter:set(strParameterValue)
            elseif strParameterConnection~=nil then
              -- This is a connection to another value or an output parameter.
              local strClass, strName = string.match(strParameterConnection, '^([^:]+):(.+)')
              if strClass==nil then
                tLogSystem.fatal(
                  'Parameter "%s" of test %d has an invalid connection "%s".',
                  strParameterName,
                  uiTestIndex,
                  strParameterConnection
                )
                tResult = nil
                break
              else
                -- Is this a connection to a system parameter?
                if strClass=='system' then
                  local tValue = self.m_atSystemParameter[strName]
                  if tValue==nil then
                    tLogSystem.fatal('The connection target "%s" has an unknown name.', strParameterConnection)
                    tResult = nil
                    break
                  else
                    tParameter:set(tostring(tValue))
                  end
                else
                  -- This is not a system parameter.
                  -- Try to interpret the class as a test number.
                  local uiConnectionTargetTestCase = tonumber(strClass)
                  if uiConnectionTargetTestCase==nil then
                    -- The class is no number. Search the name.
                    uiConnectionTargetTestCase = self:get_module_index(strClass)
                    if uiConnectionTargetTestCase==nil then
                      tLogSystem.fatal(
                        'The connection "%s" uses an unknown test name: "%s".',
                        strParameterConnection,
                        strClass
                      )
                      tResult = nil
                      break
                    end
                  end
                  if uiConnectionTargetTestCase~=nil then
                    -- Get the target module.
                    local tTargetModule = self.atModules[uiConnectionTargetTestCase]
                    if tTargetModule==nil then
                      tLogSystem.info(
                        'Ignoring the connection "%s" to an inactive target: "%s".',
                        strParameterConnection,
                        strClass
                      )
                    else
                      -- Get the parameter list of the target module.
                      local atTargetParameters = tTargetModule.atParameter or {}
                      -- Does the target module have a matching parameter?
                      local tTargetParameter = atTargetParameters[strName]
                      if tTargetParameter==nil then
                        tLogSystem.fatal(
                          'The connection "%s" uses a non-existing parameter at the target: "%s".',
                          strParameterConnection,
                          strName
                        )
                        tResult = nil
                        break
                      else
                        tLogSystem.info(
                          'Connecting %02d:%s to %02d:%s .',
                          uiTestIndex,
                          strParameterName,
                          uiConnectionTargetTestCase,
                          tTargetParameter.strName
                        )
                        tParameter:connect(tTargetParameter)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    -- Apply all parameters from the command line.
    for _, tParam in pairs(atCliParameters) do
      local uiModuleId = tParam.id
      local strParameterName = tParam.name
      tLogSystem.debug(
        'Apply CLI parameter for module #%d, "%s"="%s".',
        uiModuleId,
        strParameterName,
        tParam.value
      )

      -- Get the module.
      local tModule
      -- Do not process system parameters here.
      if uiModuleId~=0 then
        tModule = self.atModules[uiModuleId]
        if tModule==nil then
          tLogSystem.fatal('No module with index %d found.', uiModuleId)
          tResult = nil
          break
        else
          -- Get the parameter.
          local tParameter = tModule.atParameter[strParameterName]
          if tParameter==nil then
            tLogSystem.fatal('Module %d has no parameter "%s".', uiModuleId, strParameterName)
            tResult = nil
            break
          elseif tParameter.fIsOutput==true then
            tLogSystem.fatal('The parameter %02d:%s is an output parameter.', uiModuleId, strParameterName)
            tResult = nil
            break
          else
            -- Set the parameter.
            tParameter:set(tParam.value)
          end
        end
      end
    end
  end

  return tResult
end



function TestSystem:check_parameters()
  local tLogSystem = self.tLogSystem
  local tTestDescription = self.tTestDescription

  -- Check all parameters.
  local fParametersOk = true

  -- Get all test names.
  local astrTestNames = tTestDescription:getTestNames()

  -- Loop over all active tests.
  local uiNumberOfTests = tTestDescription:getNumberOfTests()
  for uiTestIndex = 1, uiNumberOfTests do
    local tModule = self.atModules[uiTestIndex]
    local strTestCaseName = astrTestNames[uiTestIndex]

    if tModule==nil then
      tLogSystem.debug('Skipping deactivated test %02d:%s .', uiTestIndex, strTestCaseName)
    else
      -- Get the parameters for the module.
      for _, tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
        -- Ignore output parameter. They will be set when the test is executed.
        if tParameter.fIsOutput==true then
          tLogSystem.debug('Ignoring output parameter %02d:%s .', uiTestIndex, tParameter.strName)

        -- Ignore also parameters connected to something. They might get their values when the test is executed.
        elseif tParameter:isConnected()==true then
          tLogSystem.debug('Ignoring the connected parameter %02d:%s .', uiTestIndex, tParameter.strName)

        else
          -- Validate the parameter.
          local fValid, strError = tParameter:validate()
          if fValid==false then
            tLogSystem.fatal('The parameter %02d:%s is invalid: %s', uiTestIndex, tParameter.strName, strError)
            fParametersOk = false
          end
        end
      end
    end
  end

  if fParametersOk==false then
    tLogSystem.fatal('One or more parameters were invalid. Not running the tests!')
  end

  return fParametersOk
end



function TestSystem:run_tests(tPackageInfo)
  local tLogSystem = self.tLogSystem
  local tTestDescription = self.tTestDescription
  local date = self.date

  local uiTestCases = tTestDescription:getNumberOfTests()

  -- Create a new "test start" event.
  local atSelection = {}
  for uiTestCase = 1, uiTestCases do
    local tModule = self.atModules[uiTestCase]
    local fRunTest = (tModule~=nil)
    table.insert(atSelection, fRunTest)
  end
  _G.tester:sendLogEvent('muhkuh.test.start', {
    package = tPackageInfo,
    selection = atSelection
  })

  -- Run all enabled modules with their parameter.
  local fTestResult = true

  -- Collect all results in the "test result" event.
  local tTestSteps = {}
  local tEventTestResult = { start=date(false):fmt('%Y-%m-%d %H:%M:%S'), steps=tTestSteps }
  for uiTestCase = 1, uiTestCases do
    local strTestCaseName
    local tModule = self.atModules[uiTestCase]
    if tModule~=nil then
      strTestCaseName = tModule.CFG_strTestName
    end
    local strTestCaseId = tTestDescription:getTestCaseId(uiTestCase)
    table.insert(tTestSteps, { name=strTestCaseName, id=strTestCaseId, state='inactive', message='' })
  end
  for _, uiTestCase in ipairs(self.auiTests) do
    tTestSteps[uiTestCase].state = 'pending'
  end

  for _, uiTestCase in ipairs(self.auiTests) do
    -- Start a new "test run" event.
    local tEventTestRun = { start=date(false):fmt('%Y-%m-%d %H:%M:%S'), parameter={} }

    local strTestCaseName = 'unknown_test'
    local strTestMessage = ''

    -- Get the module for the test index.
    local tModule = self.atModules[uiTestCase]
    if tModule==nil then
      tLogSystem.fatal('Test case %02d not found!', uiTestCase)
      fTestResult = false
    end

    if fTestResult==true then
      -- Get the name for the test case index.
      strTestCaseName = tModule.CFG_strTestName
      local strTestCaseId = tTestDescription:getTestCaseId(uiTestCase)
      self:__sendTestStepStart(uiTestCase, strTestCaseId, strTestCaseName)
      tLogSystem.info('Running testcase %d (%s).', uiTestCase, strTestCaseName)

      -- Get the parameters for the module.
      local atParameters = tModule.CFG_aParameterDefinitions

      -- Validate all input parameters.
      for _, tParameter in ipairs(atParameters) do
        if tParameter.fIsOutput~=true then
          local fValid, strError = tParameter:validate()
          if fValid==false then
            tLogSystem.fatal('Failed to validate the parameter %02d:%s : %s', uiTestCase, strTestCaseName, strError)
            fTestResult = false
            break
          end
        end
      end

      if fTestResult==true then
        -- Show all parameters for the test case.
        tLogSystem.info("__/Parameters/________________________________________________________________")
        if self.pl.tablex.size(atParameters)==0 then
          tLogSystem.info('Testcase %d (%s) has no parameter.', uiTestCase, strTestCaseName)
        else
          tLogSystem.info('Parameters for testcase %d (%s):', uiTestCase, strTestCaseName)
          for _, tParameter in pairs(atParameters) do
            -- Do not dump output parameter. They have no value yet.
            if tParameter.fIsOutput~=true then
              local strValue = tParameter:get_pretty()
              tEventTestRun.parameter[tParameter.strName] = strValue
              tLogSystem.info('  %02d:%s = %s', uiTestCase, tParameter.strName, strValue)
            end
          end
        end
        tLogSystem.info("______________________________________________________________________________")

		-- Set a hard breakpoint before the test is running - only in the case of available and running debugger
		if self.tLuaPanda ~= nil then
			self.tLuaPanda.BP()
		end

        -- Execute the test code. Write a stack trace to the debug logger if the test case crashes.
        local fStatus, tResult = xpcall(
          function()
            tModule:run()
          end,
          function(tErr)
            tLogSystem.debug(debug.traceback())
            return tErr
          end
        )
        if not fStatus then
          local strError
          if tResult~=nil then
            strError = tostring(tResult)
          else
            strError = 'No error message.'
          end
          strTestMessage = strError
          tLogSystem.error('Error running the test: %s', strError)
          tTestSteps[uiTestCase].message = strError

          fTestResult = false
        end

        -- Validate all output parameters.
        for _, tParameter in ipairs(atParameters) do
          if tParameter.fIsOutput==true then
            local fValid, strError = tParameter:validate()
            if fValid==false then
              tLogSystem.warning(
                'Failed to validate the output parameter %02d:%s : %s',
                uiTestCase,
                strTestCaseName,
                strError
              )
            end
          end
        end
      end
    end

    local strTestResult = 'SUCCESS'
    local strTestState = 'ok'
    if fTestResult~=true then
      strTestResult = 'ERROR'
      strTestState = 'error'
    end
    tTestSteps[uiTestCase].state = strTestState

    tLogSystem.info('Testcase %d (%s) finished with result %s.', uiTestCase, strTestCaseName, strTestResult)

    tEventTestRun['end'] = date(false):fmt('%Y-%m-%d %H:%M:%S')
    tEventTestRun.result = strTestState
    tEventTestRun.message = strTestMessage
    _G.tester:sendLogEvent('muhkuh.test.run', tEventTestRun)
    self:__sendTestStepFinished(strTestState)

    -- Do not execute the following test steps.
    if fTestResult~=true then
      break
    end
  end

  tEventTestResult['end'] = date(false):fmt('%Y-%m-%d %H:%M:%S')
  tEventTestResult.result = tostring(fTestResult)
  _G.tester:sendLogEvent('muhkuh.test.result', tEventTestResult)

  -- Close all connections to the netX.
  if _G.tester.closeAllCommonPlugins~=nil then
    _G.tester:closeAllCommonPlugins()
  else
    _G.tester:closeCommonPlugin()
  end

  -- Print the result in huge letters.
  if fTestResult==true then
    tLogSystem.info('***************************************')
    tLogSystem.info('*                                     *')
    tLogSystem.info('* ######## ########  ######  ######## *')
    tLogSystem.info('*    ##    ##       ##    ##    ##    *')
    tLogSystem.info('*    ##    ##       ##          ##    *')
    tLogSystem.info('*    ##    ######    ######     ##    *')
    tLogSystem.info('*    ##    ##             ##    ##    *')
    tLogSystem.info('*    ##    ##       ##    ##    ##    *')
    tLogSystem.info('*    ##    ########  ######     ##    *')
    tLogSystem.info('*                                     *')
    tLogSystem.info('*          #######  ##    ##          *')
    tLogSystem.info('*         ##     ## ##   ##           *')
    tLogSystem.info('*         ##     ## ##  ##            *')
    tLogSystem.info('*         ##     ## #####             *')
    tLogSystem.info('*         ##     ## ##  ##            *')
    tLogSystem.info('*         ##     ## ##   ##           *')
    tLogSystem.info('*          #######  ##    ##          *')
    tLogSystem.info('*                                     *')
    tLogSystem.info('***************************************')
  else
    tLogSystem.error('*******************************************************')
    tLogSystem.error('*                                                     *')
    tLogSystem.error('*         ######## ########  ######  ########         *')
    tLogSystem.error('*            ##    ##       ##    ##    ##            *')
    tLogSystem.error('*            ##    ##       ##          ##            *')
    tLogSystem.error('*            ##    ######    ######     ##            *')
    tLogSystem.error('*            ##    ##             ##    ##            *')
    tLogSystem.error('*            ##    ##       ##    ##    ##            *')
    tLogSystem.error('*            ##    ########  ######     ##            *')
    tLogSystem.error('*                                                     *')
    tLogSystem.error('* ########    ###    #### ##       ######## ########  *')
    tLogSystem.error('* ##         ## ##    ##  ##       ##       ##     ## *')
    tLogSystem.error('* ##        ##   ##   ##  ##       ##       ##     ## *')
    tLogSystem.error('* ######   ##     ##  ##  ##       ######   ##     ## *')
    tLogSystem.error('* ##       #########  ##  ##       ##       ##     ## *')
    tLogSystem.error('* ##       ##     ##  ##  ##       ##       ##     ## *')
    tLogSystem.error('* ##       ##     ## #### ######## ######## ########  *')
    tLogSystem.error('*                                                     *')
    tLogSystem.error('*******************************************************')
  end

  return fTestResult
end



function TestSystem:showPackageInformation()
  local tLog = self.tLogSystem
  local pl = self.pl
  local tPackageInfo

  -- Try to read the "package.txt" file.
  local strPackageInfoFile = pl.path.join('.jonchki', 'package.txt')
  if pl.path.isfile(strPackageInfoFile)~=true then
    tLog.warning('No version information available. The package file "%s" does not exist.', strPackageInfoFile)
  else
    tLog.debug('Reading the package file "%s".', strPackageInfoFile)
    local strError
    tPackageInfo, strError = pl.config.read(strPackageInfoFile)
    if tPackageInfo==nil then
      tLog.warning(
        'No version information available. The package file "%s" is invalid: %s',
        strPackageInfoFile,
        strError
      )
    else
      -- Check for the required fields.
      local astrRequiredFields = {
        'PACKAGE_NAME',
        'PACKAGE_VERSION',
        'PACKAGE_VCS_ID',
        'HOST_DISTRIBUTION_ID',
        'HOST_DISTRIBUTION_VERSION',
        'HOST_CPU_ARCHITECTURE'
      }
      local fAllRequiredFieldsOk = true
      for _, strKey in ipairs(astrRequiredFields) do
        if tPackageInfo[strKey]==nil then
          tLog.warning('The required field "%s" is missing in the package info file!', strKey)
          fAllRequiredFieldsOk = false
        end
      end
      if fAllRequiredFieldsOk~=true then
        tLog.warning(
          'No version information available. Some required fields are missing in the package info file "%s".',
          strPackageInfoFile
        )
        tPackageInfo = nil
      else
        tLog.info('Package info:')
        tLog.info('  Package name:              %s', tPackageInfo['PACKAGE_NAME'])
        tLog.info('  Package version:           %s', tPackageInfo['PACKAGE_VERSION'])
        tLog.info('  Package VCS ID:            %s', tPackageInfo['PACKAGE_VCS_ID'])
        tLog.info('  Host distribution ID:      %s', tPackageInfo['HOST_DISTRIBUTION_ID'])
        tLog.info('  Host distribution version: %s', tPackageInfo['HOST_DISTRIBUTION_VERSION'])
        tLog.info('  Host CPU architecture:     %s', tPackageInfo['HOST_CPU_ARCHITECTURE'])
      end
    end
  end

  return tPackageInfo
end



function TestSystem:checkIntegrity()
  local tLog = self.tLogSystem
  local mhash = self.mhash
  local pl = self.pl

  -- Try to check the package integrity.
  local fIntegrityOk = true
  local tHashID = mhash.MHASH_SHA384
  local strPackageHashFile = pl.path.join('.jonchki', 'package.sha384')
  if pl.path.isfile(strPackageHashFile)~=true then
    tLog.warning('No integrity check possible. The package file "%s" does not exist.', strPackageHashFile)
    fIntegrityOk = false
  else
    tLog.debug('Reading the package hash file "%s".', strPackageHashFile)
    local astrPackageHash, strError = self.pl.utils.readlines(strPackageHashFile)
    if astrPackageHash==nil then
      tLog.warning('No integrity check possible. Failed to read the file "%s": %s', strPackageHashFile, strError)
      fIntegrityOk = false
    else
      local uiExpectedHashStringSize = mhash.get_block_size(tHashID) * 2

      -- Loop over all lines and interpret them as hash sums.
      for uiLine, strHashLine in ipairs(astrPackageHash) do
        local strHashExpected, strFile = string.match(strHashLine, '([0-9a-fA-F]+)%s+%*?(.+)')
        if strHashExpected==nil then
          tLog.warning('Integrity error: invalid line %d in file "%s"', uiLine, strPackageHashFile)
          fIntegrityOk = false
        elseif string.len(strHashExpected)~=uiExpectedHashStringSize then
          tLog.warning('Integrity error: invalid hash size in line %d of file "%s"', uiLine, strPackageHashFile)
          fIntegrityOk = false
        elseif pl.path.isfile(strFile)~=true then
          tLog.warning('Integrity error: the file "%s" does not exist.', strFile)
          fIntegrityOk = false
        else
          tLog.debug('Hashing file "%s"...', strFile)
          -- Create a new hash state.
          local tState = mhash.mhash_state()
          tState:init(tHashID)
          -- Try to open the file.
          local tFile
          tFile, strError = io.open(strFile, 'rb')
          if tFile==nil then
            tLog.warning('Integrity error: failed to open the file "%s": %s', strFile, strError)
            fIntegrityOk = false
          else
            -- Loop over the complete file and hash the data in chunks.
            repeat
              local strData = tFile:read(16384)
              if strData~=nil then
                tState:hash(strData)
              end
            until strData==nil
            local strHashBin = tState:hash_end()
            -- Convert the binary hash to a hex dump.
            local aHashHex = {}
            for iCnt=1,string.len(strHashBin) do
              table.insert(aHashHex, string.format("%02x", string.byte(strHashBin, iCnt)))
            end
            local strHashOfFile = table.concat(aHashHex)
            -- Compare the hash of the file and the expected hash.
            if strHashOfFile~=strHashExpected then
              tLog.warning('Integrity error: the file "%s" is modified.', strFile)
              fIntegrityOk = false
            end
          end
        end
      end
    end
  end

  if fIntegrityOk==true then
    tLog.info('Package integrity: OK')
  else
    tLog.alert('Package integrity: error')
  end
end


--- Initialize the remote debugger and test the connection
function TestSystem:init_Debugger()
  local tLogSystem = self.tLogSystem

  if self.tDebugParam ~= nil then
  -- Try to load the remote debugger.
    local tResult, tLuaPanda = pcall(require, 'LuaPanda')
    if tResult ~= true then
      tLogSystem.error("Unable to load the debugger.")
    else
      -- start the client with the given IP and port number
      tLuaPanda.start(self.tDebugParam.IP,self.tDebugParam.Port)

      -- check the connection
      tResult = tLuaPanda.isConnected()
      if tResult ~= true then
        tLogSystem.error("No connection to the debugger established.")
      else
        self.tLuaPanda = tLuaPanda
      end
    end
  end
end


function TestSystem:run()
  self:parse_commandline_arguments()
  local tLogSystem = self.tLogSystem

  -- Store the system parameters here.
  self.m_atSystemParameter = {}

  -- Only in the case of available IP and port number
  self:init_Debugger()

  -- Check the test integrity.
  local tPackageInfo = self:showPackageInformation()
  self:checkIntegrity()

  -- Read the test.xml file.
  local tTestDescription = self.TestDescription(tLogSystem)
  local tResult = tTestDescription:parse('tests.xml')
  if tResult~=true then
    tLogSystem.error('Failed to parse the test description.')
  else
    self.tTestDescription = tTestDescription

    -- Run all tests if no test numbers were specified on the command line.
    local uiTestCases = tTestDescription:getNumberOfTests()
    if self.auiTests==nil then
      -- Run all tests.
      self.auiTests = {}
      for uiCnt=1, uiTestCases do
        table.insert(self.auiTests, uiCnt)
      end
    else
      -- Check if the selection does not exceed the number of tests.
      local fOk = true
      for _, uiTestIndex in ipairs(self.auiTests) do
        if uiTestIndex>uiTestCases then
          tLogSystem.error('The selected test %d exceeds the number of total tests.', uiTestIndex)
          fOk = false
        end
      end
      if fOk~=true then
        error('Invalid test index.')
      end
    end

    -- Create the global tester.
    local cTester = require 'tester_cli'
    _G.tester = cTester(tLogSystem)
    _G.tester:setSocket(self.m_zmqSocket)

    tResult = self:collect_testcases()
    if tResult==true then
      if self.fShowParameters==true then
        self:show_all_parameters()
      else
        tResult = self:collect_parameters()
        if tResult==true then
          tResult = self:check_parameters()
          if tResult==true then
            self:__sendTestRunStart()

            tResult = self:run_tests(tPackageInfo)
          end
        end
      end
    end
  end

  self:__sendTestRunFinished()
  self:__disconnect()

  local iResult = 1
  if tResult==true then
    iResult = 0
  end
  return iResult
end


return TestSystem
