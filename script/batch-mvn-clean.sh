pwd
echo '遍历并清理当前目录下target, mvn clean'
for element in `ls`
do  
    #element 表示location1目录下各个文件
	echo $element
	# 判断是否为文件夹
	if [ -d $element ]; then
		cd $element
		# Quiet output - only show errors
		mvn -q clean
		# ls -a pom.xml
		cd ..
	fi
done
echo "Finish farem!"

read -n1 -p "Press any key to continue..."